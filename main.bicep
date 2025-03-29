param location string = 'francecentral'
param cosmosDbAccountName string = 'dbtarefas'
param databaseName string = 'GestorTarefasDB'
param containerAppName string = 'gestor-tarefas-backend'
param containerEnvName string = 'tarefas-env'
param githubRepoUrl string = 'https://github.com/Mr-Cracked/Gestor-Tarefas'
param githubBranch string = 'main'
param containerPort int = 3000

// Cosmos DB Account
resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosDbAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
  }
}

// Cosmos DB Database
resource cosmosDbDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosDb
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

// Container: Users
resource usersContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDbDatabase
  name: 'Utilizador'
  properties: {
    resource: {
      id: 'Utilizador'
      partitionKey: {
        paths: ['/email']
        kind: 'Hash'
      }
    }
  }
}

// Container: Tasks
resource tasksContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDbDatabase
  name: 'Tarefa'
  properties: {
    resource: {
      id: 'Tarefa'
      partitionKey: {
        paths: ['/email']
        kind: 'Hash'
      }
    }
  }
}
/*
// Secret para acesso ao Blob
resource storageKeys 'Microsoft.Storage/storageAccounts/listKeys/action@2023-01-01' = {
  name: 'listKeys'
  parent: storageAccount
}

var connectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageKeys.value.keys[0].value};EndpointSuffix=core.windows.net'

containerApp.properties.configuration.secrets += [
  {
    name: 'storage-connection-string'
    value: connectionString
  }
]

// E depois podes usar no container:
containerApp.properties.template.containers[0].env += [
  {
    name: 'AZURE_STORAGE_CONNECTION_STRING'
    secretRef: 'storage-connection-string'
  }
]*/


/*
// Container App Environment
resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerEnvName
  location: location
  properties: {}
}

// Container App (build from GitHub repo, subfolder: BackEnd)
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: containerPort
      }
      secrets: [
        {
          name: 'cosmosdb-key'
          value: listKeys(cosmosDb.id, '2023-04-15').primaryMasterKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerAppName
          image: 'ghcr.io/placeholder/temp' // temporário; será substituído pela build
          env: [
            {
              name: 'COSMOS_DB_URL'
              value: cosmosDb.properties.documentEndpoint
            }
            {
              name: 'COSMOS_DB_KEY'
              secretRef: 'cosmosdb-key'
            }
          ]
        }
      ]
    }
    source: {
      type: 'GitHub'
      repoUrl: githubRepoUrl
      branch: githubBranch
      dockerfile: 'BackEnd/Dockerfile'
    }
  }
}
*/
output cosmosDbEndpoint string = cosmosDb.properties.documentEndpoint
output cosmosDbKey string = listKeys(cosmosDb.id, '2023-04-15').primaryMasterKey
//output containerAppUrl string = 'https://${containerAppName}.${location}.azurecontainerapps.io'
