// Copyright 2016-2020, Pulumi Corporation.  All rights reserved.
import * as azuread from "@pulumi/azuread"
import * as pulumi from "@pulumi/pulumi"
import * as random from "@pulumi/random"
import * as k8s from "@pulumi/kubernetes"

import * as containerservice from "@pulumi/azure-native/containerservice"
import * as resources from "@pulumi/azure-native/resources"
import * as containerregistry from "@pulumi/azure-native/containerregistry"
import * as managedidentity from "@pulumi/azure-native/managedidentity"
import * as authorization from "@pulumi/azure-native/authorization"

const subscriptionId = "9038a2ab-d43e-4131-8178-ab84de4e2947"

// Create an Azure Resource Group
const resourceGroup = new resources.ResourceGroup("azure-go-aks", {
	resourceGroupName: "azure-aks-pulumi-test"
})

// User assigned identity for the cluster
const clusterIdentity = new managedidentity.UserAssignedIdentity(
	"aks-identity",
	{
		resourceGroupName: resourceGroup.name,
		resourceName: "azure-aks-managed-identity"
	}
)

// Create ACR
const acr = new containerregistry.Registry("azure-go-aks-acr", {
	registryName: "akspulumitestregistry",
	resourceGroupName: resourceGroup.name,
	sku: { name: containerregistry.SkuName.Basic }
})

const roleAssignment = new authorization.RoleAssignment(
	"aks-acr-role-assignment",
	{
		principalId: clusterIdentity.principalId,
		principalType: authorization.PrincipalType.ServicePrincipal,
		roleDefinitionId: `/subscriptions/${subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d`,
		scope: acr.id
	}
)

const getUserAssignedIdentitiesForManagedCluster = (id: string) => {
	const dict: { [key: string]: object } = {}
	dict[id] = {}
	return dict
}
const config = new pulumi.Config()
const managedClusterName = config.get("managedClusterName") || "azure-aks"
const cluster = new containerservice.ManagedCluster(managedClusterName, {
	resourceGroupName: resourceGroup.name,
	agentPoolProfiles: [
		{
			count: 1,
			maxPods: 110,
			mode: "System",
			name: "agentpool",
			osType: containerservice.OSType.Linux,
			vmSize: "Standard_B2s"
		}
	],
	dnsPrefix: resourceGroup.name,
	enableRBAC: true,
	nodeResourceGroup: `MC_azure-go_${managedClusterName}`,
	identity: {
		type: containerservice.ResourceIdentityType.UserAssigned,
		userAssignedIdentities: clusterIdentity.id.apply((id) =>
			getUserAssignedIdentitiesForManagedCluster(id)
		)
	}
})

const creds = containerservice.listManagedClusterUserCredentialsOutput({
	resourceGroupName: resourceGroup.name,
	resourceName: cluster.name
})

const encoded = creds.kubeconfigs[0].value
const kubeconfig = encoded.apply((enc) => Buffer.from(enc, "base64").toString())

const k8sProvider = new k8s.Provider("k8s-provider", {
	kubeconfig: kubeconfig
})

const argoNS = new k8s.core.v1.Namespace(
	"argocd-namespace",
	{
		metadata: {
			name: "argocd"
		}
	},
	{ provider: k8sProvider, dependsOn: [cluster] }
)

const argocd = new k8s.yaml.ConfigFile(
	"argocd",
	{
		file: "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml",
		transformations: [
			(obj: any, opts: pulumi.CustomResourceOptions) => {
				if (!obj.metadata.namespace)
					obj.metadata.namespace = argoNS.metadata.name
			}
		]
	},
	{ provider: k8sProvider, dependsOn: [argoNS] }
)

new k8s.yaml.ConfigFile(
	"todo-argocd-app",
	{
		file: "./argocd/todo-app.yaml"
	},
	{ provider: k8sProvider, dependsOn: [argocd] }
)

new k8s.yaml.ConfigFile(
	"traefik-argocd-app",
	{
		file: "./argocd/traefik.yaml"
	},
	{ provider: k8sProvider, dependsOn: [argocd] }
)
