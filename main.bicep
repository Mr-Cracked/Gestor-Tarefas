param location string = 'francecentral'
param cosmosDbAccountName string = 'dbtarefas'
param databaseName string = 'GestorTarefasDB'

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

output cosmosDbEndpoint string = cosmosDb.properties.documentEndpoint
output cosmosDbKey string = listKeys(cosmosDb.id, '2023-04-15').primaryMasterKey
