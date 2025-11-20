package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"
)

const (
	schedulerName        = "custom-scheduler"
	defaultCacheFile     = "/cache/carbon_cache.json" // Kubernetes path (PVC mount)
	carbonAwareLabel     = "carbon-aware"
	regionLabel          = "carbon-region" // Node label to map to Wattime region
	defaultRegionLabel   = "region"        // Fallback label
)

var (
	carbonAwareMode = os.Getenv("CARBON_AWARE_MODE") != "false" // Default to true
	cacheFile       = getEnvOrDefault("CACHE_FILE", defaultCacheFile)
)

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func main() {
	// Connect to Kubernetes
	config, err := clientcmd.BuildConfigFromFlags("", clientcmd.RecommendedHomeFile)
	if err != nil {
		config, err = rest.InClusterConfig()
		if err != nil {
			panic(err.Error())
		}
	}

	// Kubectl for Go
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}
	fmt.Println("Connected to Kubernetes API")
	
	if carbonAwareMode {
		fmt.Printf("Carbon-aware scheduling ENABLED (cache: %s)\n", cacheFile)
	} else {
		fmt.Println("Carbon-aware scheduling DISABLED (non-carbon-aware mode)")
	}

	// Watch for unscheduled pods
	watchlist := cache.NewListWatchFromClient(
		clientset.CoreV1().RESTClient(),
		"pods",
		metav1.NamespaceAll,
		fields.OneTermEqualSelector("spec.nodeName", ""),
	)

	_, controller := cache.NewInformer(
		watchlist,
		&corev1.Pod{},
		0,
		cache.ResourceEventHandlerFuncs{
			AddFunc: func(obj interface{}) {
				pod := obj.(*corev1.Pod)

				// Only handle pods requesting our scheduler
				if pod.Spec.SchedulerName != schedulerName {
					return
				}

				fmt.Printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
				fmt.Printf("Unscheduled pod detected: %s/%s\n", pod.Namespace, pod.Name)
				podCPU, podMemory := getPodResourceRequests(pod)
				fmt.Printf("Pod resource requests: CPU=%s Memory=%s\n", 
					formatResource(podCPU), formatResource(podMemory))
				nodeName := findBestNodeForPod(pod, clientset)
				if nodeName != "" {
					err := schedulePodToNode(pod, nodeName, clientset)
					if err != nil {
						fmt.Printf("❌ Failed to schedule pod %s to node %s: %v\n", pod.Name, nodeName, err)
					} else {
						fmt.Printf("✅ Pod %s scheduled to %s\n", pod.Name, nodeName)
					}
				} else {
					fmt.Printf("❌ No suitable node found for pod %s\n", pod.Name)
				}
				fmt.Printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
			},
		},
	)

	stop := make(chan struct{})
	defer close(stop)
	go controller.Run(stop)

	// Keep main thread alive
	select {}
}

// Carbon intensity cache structure
type CarbonCache struct {
	Timestamp   string            `json:"timestamp"`
	TTLMinutes  int               `json:"ttl_minutes"`
	Regions     map[string]Region `json:"regions"`
	SortedByCarbon []string       `json:"sorted_by_carbon"`
	BestRegion  string            `json:"best_region"`
	WorstRegion string            `json:"worst_region"`
}

type Region struct {
	Zone              string  `json:"zone"`
	CarbonIntensity   float64 `json:"carbonIntensity"` // g CO2/kWh (Electricity Maps)
	MOER              float64 `json:"moer"`             // Legacy WattimeAPI field
	Datetime          string  `json:"datetime"`
	UpdatedAt         string  `json:"updatedAt"`
	CreatedAt         string  `json:"createdAt"`
	EmissionFactorType string  `json:"emissionFactorType"`
	IsEstimated       bool    `json:"isEstimated"`
	EstimationMethod  string  `json:"estimationMethod"`
	Timestamp         string  `json:"timestamp"`
}

// Read carbon cache from file
func readCarbonCache() (*CarbonCache, error) {
	data, err := os.ReadFile(cacheFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read cache file: %w", err)
	}

	// First unmarshal into a generic map to check structure
	var rawData map[string]interface{}
	if err := json.Unmarshal(data, &rawData); err != nil {
		return nil, fmt.Errorf("failed to parse cache: %w", err)
	}

	// Handle nested regions structure (backward compatibility fix)
	if regionsRaw, ok := rawData["regions"].(map[string]interface{}); ok {
		// Check if nested: regions.regions
		if nestedRegions, ok := regionsRaw["regions"].(map[string]interface{}); ok {
			// Flatten the structure
			rawData["regions"] = nestedRegions
		}
	}

	// Now unmarshal into proper struct
	var cache CarbonCache
	cacheBytes, _ := json.Marshal(rawData)
	if err := json.Unmarshal(cacheBytes, &cache); err != nil {
		return nil, fmt.Errorf("failed to unmarshal cache: %w", err)
	}

	// Check if cache is expired
	if cache.Timestamp != "" {
		timestamp, err := time.Parse(time.RFC3339, cache.Timestamp)
		if err == nil {
			age := time.Since(timestamp)
			if age > time.Duration(cache.TTLMinutes)*time.Minute {
				return nil, fmt.Errorf("cache expired (age: %v)", age)
			}
		}
	}

	return &cache, nil
}

// Get region for a node (from labels)
func getNodeRegion(node *corev1.Node) string {
	// Try carbon-region label first
	if region := node.Labels[regionLabel]; region != "" {
		return region
	}
	// Fallback to region label
	if region := node.Labels[defaultRegionLabel]; region != "" {
		return region
	}
	// Try zone as fallback
	if zone := node.Labels["topology.kubernetes.io/zone"]; zone != "" {
		return zone
	}
	return ""
}

// Calculate total resource requests for a pod
func getPodResourceRequests(pod *corev1.Pod) (cpu, memory resource.Quantity) {
	cpu = resource.Quantity{}
	memory = resource.Quantity{}

	for _, container := range pod.Spec.Containers {
		if req := container.Resources.Requests; req != nil {
			if cpuReq, ok := req[corev1.ResourceCPU]; ok {
				cpu.Add(cpuReq)
			}
			if memReq, ok := req[corev1.ResourceMemory]; ok {
				memory.Add(memReq)
			}
		}
	}

	return cpu, memory
}

// Format resource quantity for logging
func formatResource(q resource.Quantity) string {
	if q.IsZero() {
		return "none"
	}
	return q.String()
}

// Calculate allocated resources on a node (sum of all pods' requests)
func getNodeAllocatedResources(nodeName string, clientset *kubernetes.Clientset) (cpu, memory resource.Quantity, err error) {
	cpu = resource.Quantity{}
	memory = resource.Quantity{}

	// Get all pods on this node
	pods, err := clientset.CoreV1().Pods("").List(context.Background(), metav1.ListOptions{
		FieldSelector: fmt.Sprintf("spec.nodeName=%s", nodeName),
	})
	if err != nil {
		return cpu, memory, err
	}

	// Sum up resource requests from all pods
	for _, pod := range pods.Items {
		// Skip pods that are being deleted
		if pod.DeletionTimestamp != nil {
			continue
		}

		for _, container := range pod.Spec.Containers {
			if req := container.Resources.Requests; req != nil {
				if cpuReq, ok := req[corev1.ResourceCPU]; ok {
					cpu.Add(cpuReq)
				}
				if memReq, ok := req[corev1.ResourceMemory]; ok {
					memory.Add(memReq)
				}
			}
		}
	}

	return cpu, memory, nil
}

// Check if node has enough resources for the pod
func nodeHasResources(node *corev1.Node, pod *corev1.Pod, clientset *kubernetes.Clientset) bool {
	// Get pod resource requests
	podCPU, podMemory := getPodResourceRequests(pod)

	// If pod has no resource requests, assume it fits
	if podCPU.IsZero() && podMemory.IsZero() {
		return true
	}

	// Get node allocatable resources
	nodeCPU, ok := node.Status.Allocatable[corev1.ResourceCPU]
	if !ok {
		return false
	}
	nodeMemory, ok := node.Status.Allocatable[corev1.ResourceMemory]
	if !ok {
		return false
	}

	// Get currently allocated resources on this node
	allocatedCPU, allocatedMemory, err := getNodeAllocatedResources(node.Name, clientset)
	if err != nil {
		fmt.Printf("Warning: Could not get allocated resources for node %s: %v\n", node.Name, err)
		// If we can't check, be conservative and skip this node
		return false
	}

	// Calculate available resources
	availableCPU := nodeCPU.DeepCopy()
	availableCPU.Sub(allocatedCPU)

	availableMemory := nodeMemory.DeepCopy()
	availableMemory.Sub(allocatedMemory)

	// Check if node has enough resources
	hasCPU := availableCPU.Cmp(podCPU) >= 0
	hasMemory := availableMemory.Cmp(podMemory) >= 0

	if !hasCPU || !hasMemory {
		fmt.Printf("Node %s: insufficient resources (CPU: %s/%s available, Memory: %s/%s available, Pod needs: CPU=%s Memory=%s)\n",
			node.Name,
			availableCPU.String(), nodeCPU.String(),
			availableMemory.String(), nodeMemory.String(),
			podCPU.String(), podMemory.String())
		return false
	}

	return true
}

// Find best node using carbon-aware scheduling
func findBestNodeForPod(pod *corev1.Pod, clientset *kubernetes.Clientset) string {
	nodes, err := clientset.CoreV1().Nodes().List(context.Background(), metav1.ListOptions{})
	if err != nil {
		fmt.Printf("Error listing nodes: %v\n", err)
		return ""
	}

	if len(nodes.Items) == 0 {
		fmt.Println("No nodes available for scheduling")
		return ""
	}

	// Filter nodes that can run the pod
	availableNodes := []corev1.Node{}
	for _, node := range nodes.Items {
		// Check if node is ready
		isReady := false
		for _, condition := range node.Status.Conditions {
			if condition.Type == corev1.NodeReady && condition.Status == corev1.ConditionTrue {
				isReady = true
				break
			}
		}
		if !isReady {
			fmt.Printf("Node %s: not ready\n", node.Name)
			continue
		}

		// Check node taints
		canSchedule := true
		for _, taint := range node.Spec.Taints {
			if taint.Effect == corev1.TaintEffectNoSchedule {
				canSchedule = false
				fmt.Printf("Node %s: has NoSchedule taint\n", node.Name)
				break
			}
		}
		if !canSchedule {
			continue
		}

		// Check if node has enough resources
		if !nodeHasResources(&node, pod, clientset) {
			continue
		}

		availableNodes = append(availableNodes, node)
		fmt.Printf("Node %s: available (passed all checks)\n", node.Name)
	}

	if len(availableNodes) == 0 {
		fmt.Println("No available nodes for scheduling")
		return ""
	}

	// Non-carbon-aware mode: return first available node
	if !carbonAwareMode {
		fmt.Printf("Non-carbon-aware: scheduling to %s\n", availableNodes[0].Name)
		return availableNodes[0].Name
	}

	// Carbon-aware mode: read cache and select best node
	cache, err := readCarbonCache()
	if err != nil {
		fmt.Printf("Warning: Could not read carbon cache (%v), falling back to first node\n", err)
		return availableNodes[0].Name
	}

	fmt.Printf("Carbon cache loaded: %d regions, best: %s\n", len(cache.Regions), cache.BestRegion)

	// Score nodes based on carbon intensity
	type nodeScore struct {
		node  corev1.Node
		score float64 // Lower is better (lower carbon intensity)
		region string
	}

	scores := []nodeScore{}
	for _, node := range availableNodes {
		region := getNodeRegion(&node)
		score := float64(1000) // Default high score if region not found

		if region != "" {
			if regionData, ok := cache.Regions[region]; ok {
				// Use carbonIntensity (Electricity Maps) or fall back to MOER (WattimeAPI)
				if regionData.CarbonIntensity > 0 {
					score = regionData.CarbonIntensity
				} else if regionData.MOER > 0 {
					score = regionData.MOER
				}
				fmt.Printf("Node %s: region=%s, Carbon Intensity=%.2f g CO2/kWh\n", node.Name, region, score)
			} else {
				fmt.Printf("Node %s: region=%s (not in cache)\n", node.Name, region)
			}
		} else {
			fmt.Printf("Node %s: no region label found\n", node.Name)
		}

		scores = append(scores, nodeScore{
			node:  node,
			score: score,
			region: region,
		})
	}

	// Sort by score (lowest carbon intensity first)
	bestNode := scores[0]
	for _, s := range scores {
		if s.score < bestNode.score {
			bestNode = s
		}
	}

	// Log all node scores for verification
	fmt.Printf("\n📊 Node Scoring Summary:\n")
	for _, s := range scores {
		marker := " "
		if s.node.Name == bestNode.node.Name {
			marker = "⭐"
		}
		fmt.Printf("  %s %s: region=%s, Carbon Intensity=%.2f g CO2/kWh\n", 
			marker, s.node.Name, s.region, s.score)
	}
	
	fmt.Printf("\n✅ Carbon-aware decision: %s (region=%s, Carbon Intensity=%.2f g CO2/kWh)\n", 
		bestNode.node.Name, bestNode.region, bestNode.score)
	return bestNode.node.Name
}

// Bind pod to the chosen node using proper Binding API
func schedulePodToNode(pod *corev1.Pod, nodeName string, clientset *kubernetes.Clientset) error {
	binding := &corev1.Binding{
		ObjectMeta: metav1.ObjectMeta{
			Name:      pod.Name,
			Namespace: pod.Namespace,
		},
		Target: corev1.ObjectReference{
			Kind: "Node",
			Name: nodeName,
		},
	}
	return clientset.CoreV1().Pods(pod.Namespace).Bind(context.Background(), binding, metav1.CreateOptions{})
}
