@description('Azure region for all resources.')
param location string = resourceGroup().location
@description('Short globally unique prefix using lowercase letters, digits, and hyphens.')
@minLength(5)
@maxLength(18)
param namePrefix string
@description('Microsoft Entra tenant GUID used to validate API access tokens.')
param entraTenantId string
@description('Exact API audience claim accepted in Entra v2 access tokens.')
param entraApiAudience string
@description('Contact email shown in the APIM publisher profile.')
param publisherEmail string
@secure()
@description('High-entropy shared value APIM injects and the backend checks.')
param backendSharedKey string

var acrName = take(replace(toLower('${namePrefix}acr'), '-', ''), 50)
var appServiceName = '${namePrefix}-web'
var containerAppName = '${namePrefix}-api'
var apimName = '${namePrefix}-apim'
var caEnvName = '${namePrefix}-cae'
var planName = '${namePrefix}-plan'

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false, publicNetworkAccess: 'Enabled' }
}

resource caEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: caEnvName
  location: location
  properties: { appLogsConfiguration: { destination: 'azure-monitor' } }
}

resource apiApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: caEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      registries: [ { server: registry.properties.loginServer, identity: 'system' } ]
      ingress: { external: true, targetPort: 80, transport: 'http', allowInsecure: false }
      secrets: [ { name: 'backend-shared-key', value: backendSharedKey } ]
    }
    template: {
      containers: [ {
        name: 'api'
        image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
        env: [ { name: 'BACKEND_SHARED_KEY', secretRef: 'backend-shared-key' } ]
        resources: { cpu: json('0.5'), memory: '1Gi' }
      } ]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, apiApp.id, 'AcrPull')
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: apiApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource appPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: { name: 'B1', tier: 'Basic', size: 'B1', capacity: 1 }
  properties: { reserved: true }
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux,container'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appPlan.id
    httpsOnly: true
    siteConfig: {
      acrUseManagedIdentityCreds: true
      linuxFxVersion: 'DOCKER|nginx:alpine'
      appSettings: [
        { name: 'WEBSITES_PORT', value: '80' }
        { name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE', value: 'false' }
        { name: 'DOCKER_REGISTRY_SERVER_URL', value: 'https://${registry.properties.loginServer}' }
        { name: 'DOCKER_REGISTRY_SERVER_USERNAME', value: '' }
        { name: 'DOCKER_REGISTRY_SERVER_PASSWORD', value: '' }
        { name: 'ENTRA_TENANT_ID', value: entraTenantId }
        { name: 'ENTRA_CLIENT_ID', value: '' }
        { name: 'ENTRA_API_SCOPE', value: '' }
        { name: 'APIM_API_BASE_URL', value: '' }
        { name: 'APIM_SUBSCRIPTION_KEY', value: '' }
      ]
      alwaysOn: true
      healthCheckPath: '/'
    }
  }
}

resource appAcrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, webApp.id, 'AcrPull')
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  sku: { name: 'Developer', capacity: 1 }
  properties: {
    publisherEmail: publisherEmail
    publisherName: 'API Demo'
  }
}

resource apimBackendKey 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'backend-shared-key'
  properties: { displayName: 'backend-shared-key', value: backendSharedKey, secret: true }
}

resource apimTenant 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'entra-tenant-id'
  properties: { displayName: 'entra-tenant-id', value: entraTenantId, secret: false }
}

resource apimAudience 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'entra-api-audience'
  properties: { displayName: 'entra-api-audience', value: entraApiAudience, secret: false }
}

resource apimBackendHost 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'backend-host'
  properties: { displayName: 'backend-host', value: apiApp.properties.configuration.ingress.fqdn, secret: false }
}

resource apimFrontendOrigin 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'frontend-origin'
  properties: { displayName: 'frontend-origin', value: 'https://${webApp.properties.defaultHostName}', secret: false }
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'demo'
  properties: {
    displayName: 'Demo Python API'
    path: 'demo'
    protocols: [ 'https' ]
    subscriptionRequired: true
    serviceUrl: 'https://${apiApp.properties.configuration.ingress.fqdn}'
    isCurrent: true
  }
}

resource helloOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: api
  name: 'hello'
  properties: {
    displayName: 'Hello'
    method: 'GET'
    urlTemplate: '/api/v1/hello'
    responses: [ { statusCode: 200, description: 'Protected hello response' } ]
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('apim-policy.xml')
  }
  dependsOn: [apimBackendKey, apimTenant, apimAudience, apimBackendHost, apimFrontendOrigin]
}

output registryName string = registry.name
output registryLoginServer string = registry.properties.loginServer
output appServiceName string = webApp.name
output appServiceUrl string = 'https://${webApp.properties.defaultHostName}'
output containerAppName string = apiApp.name
output backendUrl string = 'https://${apiApp.properties.configuration.ingress.fqdn}'
output apimName string = apim.name
output apimGatewayUrl string = 'https://${apim.name}.azure-api.net'
