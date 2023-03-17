// Deploying Azure Functions App to Azure
//
// Author: Bernhard Flür
// Date: 17-03-2023
// Version: 1.0

// Define parameters
param AppName string
param location string = resourceGroup().location
param BackupSchedule string = '0 3 * * * *'


// Define variables
var storageAccountName = '${uniqueString(resourceGroup().id)}azfunctions'
var storageAccountType = 'Standard_LRS'
var FunctionAppName = AppName
var HostPlanName = '${AppName}-plan'
var appInsightsName = '${AppName}-Insights'


// Define resources
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountType
  }
  kind: 'Storage'
}

resource hostPlan 'Microsoft.Web/serverfarms@2020-12-01' = {
  name: HostPlanName
  location: location
  sku: {
    name: 'EP1'
    tier: 'Dynamic'
  }
  properties: {}
}

resource insightsComponents 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource azureFunctionApp 'Microsoft.Web/sites@2020-12-01' = {
  name: FunctionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: hostPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsDashboard'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower('name')
        }
        {
          name: 'StorageAccountNameSource'
          value: '<Fill in your source storage account name>'
        }
        {
          name: 'StorageAccountNameTarget'
          value: '<Fill in your target storage account name>'
        }
        {
          name: 'RGNameSource'
          value: '<Fill in your source resource group name>'
        }
        {
          name: 'RGNameTarget'
          value: '<Fill in your target resource group name>'
        }
        {
          name: 'BackupSchedule'
          value: BackupSchedule
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: insightsComponents.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource function 'Microsoft.Web/sites/functions@2022-03-01' = {
  parent: azureFunctionApp
  name: 'BackupTable'
  properties: {
    language: 'PowerShell'
    config: {
      bindings: [
        {
          name: 'Timer'
          type: 'timerTrigger'
          direction: 'in'
          schedule: '%BackupSchedule%'
        }
      ]
      disabled: false
    }
    files: {
      'run.ps1' : loadTextContent('../FunctionApp/DailyBackup/run.ps1')
      '../requirements.psd1' : loadTextContent('../FunctionApp/requirements.psd1')
    }
  }
}
