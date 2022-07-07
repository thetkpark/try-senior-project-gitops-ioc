// Copyright 2016-2020, Pulumi Corporation.  All rights reserved.
import * as azuread from "@pulumi/azuread";
import * as pulumi from "@pulumi/pulumi";
import * as random from "@pulumi/random";
import * as k8s from "@pulumi/kubernetes";

import * as containerservice from "@pulumi/azure-native/containerservice";
import * as resources from "@pulumi/azure-native/resources";
import * as containerregistry from "@pulumi/azure-native/containerregistry";

// Create an Azure Resource Group
const resourceGroup = new resources.ResourceGroup("azure-go-aks", { resourceGroupName: "azure-aks-pulumi-test" });

// Create ACR
const acr = new containerregistry.Registry("azure-go-aks-acr", {registryName: 'akspulumitestregistry', resourceGroupName: resourceGroup.name, sku: { name: containerregistry.SkuName.Basic }});

const config = new pulumi.Config();
const managedClusterName = config.get("managedClusterName") || "azure-aks";
const cluster = new containerservice.ManagedCluster(managedClusterName, {
    resourceGroupName: resourceGroup.name,
    agentPoolProfiles: [{
        count: 1,
        maxPods: 110,
        mode: "System",
        name: "agentpool",
        osType: containerservice.OSType.Linux,
        vmSize: "Standard_B2s",
    }],
    dnsPrefix: resourceGroup.name,
    enableRBAC: true,
    nodeResourceGroup: `MC_azure-go_${managedClusterName}`,
    identity: {
        type: containerservice.ResourceIdentityType.SystemAssigned,
    }
});

const creds = containerservice.listManagedClusterUserCredentialsOutput({
    resourceGroupName: resourceGroup.name,
    resourceName: cluster.name,
});

const encoded = creds.kubeconfigs[0].value;
const kubeconfig = encoded.apply(enc => Buffer.from(enc, "base64").toString());

const k8sProvider = new k8s.Provider("k8s-provider", {
    kubeconfig: kubeconfig,
});

const argoNS = new k8s.core.v1.Namespace("argocd-namespace", {
    metadata: {
        name: "argocd",
    }
}, {provider: k8sProvider, dependsOn: [cluster]})

new k8s.yaml.ConfigFile("argocd", {
    file: 'https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml',
    transformations: [(obj: any, opts: pulumi.CustomResourceOptions) => {
        if (!obj.metadata.namespace) obj.metadata.namespace = argoNS.metadata.name;
    }]
}, {provider: k8sProvider, dependsOn: [argoNS]})