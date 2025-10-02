package main

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"
)

const schedulerName = "custom-scheduler"

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
				nodeName := findBestNodeForPod(pod, clientset)
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

// Naive scheduler: pick the first available node
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

	return nodes.Items[0].Name
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
