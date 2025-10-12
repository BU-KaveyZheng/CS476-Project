package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"sort"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"
)

const schedulerName = "carbon-aware-scheduler"

// NodeCarbonInfo holds carbon intensity information for a node
type NodeCarbonInfo struct {
	NodeName         string
	CarbonIntensity  float64
	Zone             string
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

	// Initialize carbon intensity client
	carbonClient, err := NewCarbonClient()
	if err != nil {
		log.Printf("Warning: Carbon intensity client initialization failed: %v", err)
		log.Println("Scheduler will run without carbon awareness")
		carbonClient = nil
	} else {
		fmt.Println("Carbon intensity client initialized successfully")
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

				fmt.Printf("Unscheduled pod detected: %s/%s\n", pod.Namespace, pod.Name)
				nodeName := findBestNodeForPod(pod, clientset, carbonClient)
				if nodeName != "" {
					err := schedulePodToNode(pod, nodeName, clientset)
					if err != nil {
						fmt.Printf("Failed to schedule pod %s to node %s: %v\n", pod.Name, nodeName, err)
					} else {
						fmt.Printf("Pod %s scheduled to %s\n", pod.Name, nodeName)
					}
				}
			},
		},
	)

	stop := make(chan struct{})
	defer close(stop)
	go controller.Run(stop)

	// Keep main thread alive
	select {}
}

// Carbon-aware scheduler: pick the node with the lowest carbon intensity
func findBestNodeForPod(pod *corev1.Pod, clientset *kubernetes.Clientset, carbonClient *CarbonClient) string {
	nodes, err := clientset.CoreV1().Nodes().List(context.Background(), metav1.ListOptions{})
	if err != nil {
		fmt.Printf("Error listing nodes: %v\n", err)
		return ""
	}

	if len(nodes.Items) == 0 {
		fmt.Println("No nodes available for scheduling")
		return ""
	}

	// If carbon client is not available, fall back to naive scheduling
	if carbonClient == nil {
		fmt.Println("Carbon client not available, using naive scheduling")
		return nodes.Items[0].Name
	}

	// Get carbon intensity for each node
	var nodeCarbonInfos []NodeCarbonInfo
	for _, node := range nodes.Items {
		// Skip nodes that are not ready
		if !isNodeReady(&node) {
			continue
		}

		// Get zone from node labels or use default
		zone := getNodeZone(&node)
		
		// Get carbon intensity for this zone
		carbonIntensity, err := carbonClient.GetAverageCarbonIntensity(zone, 1) // Last 1 hour average
		if err != nil {
			fmt.Printf("Warning: Could not get carbon intensity for zone %s: %v\n", zone, err)
			// Use a high default value to deprioritize this node
			carbonIntensity = 1000
		}

		nodeCarbonInfos = append(nodeCarbonInfos, NodeCarbonInfo{
			NodeName:        node.Name,
			CarbonIntensity: carbonIntensity,
			Zone:           zone,
		})
	}

	if len(nodeCarbonInfos) == 0 {
		fmt.Println("No ready nodes available for scheduling")
		return ""
	}

	// Sort nodes by carbon intensity (lowest first)
	sort.Slice(nodeCarbonInfos, func(i, j int) bool {
		return nodeCarbonInfos[i].CarbonIntensity < nodeCarbonInfos[j].CarbonIntensity
	})

	bestNode := nodeCarbonInfos[0]
	fmt.Printf("Selected node %s in zone %s with carbon intensity %.2f gCO₂eq/kWh\n", 
		bestNode.NodeName, bestNode.Zone, bestNode.CarbonIntensity)

	return bestNode.NodeName
}

// isNodeReady checks if a node is ready for scheduling
func isNodeReady(node *corev1.Node) bool {
	for _, condition := range node.Status.Conditions {
		if condition.Type == corev1.NodeReady {
			return condition.Status == corev1.ConditionTrue
		}
	}
	return false
}

// getNodeZone extracts the zone from node labels or returns a default
func getNodeZone(node *corev1.Node) string {
	// Check for common zone labels
	if zone, exists := node.Labels["topology.kubernetes.io/zone"]; exists {
		return zone
	}
	if zone, exists := node.Labels["failure-domain.beta.kubernetes.io/zone"]; exists {
		return zone
	}
	if zone, exists := node.Labels["carbon-zone"]; exists {
		return zone
	}
	
	// Default zone based on environment variable or fallback
	defaultZone := os.Getenv("DEFAULT_CARBON_ZONE")
	if defaultZone == "" {
		defaultZone = "DE" // Default to Germany
	}
	return defaultZone
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
