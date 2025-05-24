# ================================
# Parametros principais
# ================================
$rg = "gestorTarefasCN"
$location = "francecentral"
$cosmosName = "gestortarefas202203"
$dbName = "GestorTarefasDB"
$containerName = "gestor-tarefas-backend"
$dnsLabel = "gestor-tarefas-api-compnuv"

# Azure Container Registry
$acrName = "gestortarefasacr202203"
$imageName = "gestor-tarefas:latest"
$acrLoginServer = "$acrName.azurecr.io"

# GitHub
$gitRepo = "https://github.com/Mr-Cracked/Gestor-Tarefas.git"
$gitBranch = "main"

# ================================
# Criar Resource Group
# ================================
Write-Host "`nA criar Resource Group: $rg..."
az group create --name $rg --location $location

# ================================
# Cosmos DB + BD + Containers
# ================================
Write-Host "`nA criar conta Cosmos DB: $cosmosName..."
az cosmosdb create `
  --name $cosmosName `
  --resource-group $rg `
  --locations regionName=$location failoverPriority=0 `
  --default-consistency-level Session `
  --kind GlobalDocumentDB

Write-Host "`nA criar base de dados '$dbName'..."
az cosmosdb sql database create `
  --account-name $cosmosName `
  --resource-group $rg `
  --name $dbName

Write-Host "`nA criar container 'Utilizador'..."
az cosmosdb sql container create `
  --account-name $cosmosName `
  --resource-group $rg `
  --database-name $dbName `
  --name Utilizador `
  --partition-key-path "/email"

Write-Host "`nA criar container 'Tarefa'..."
az cosmosdb sql container create `
  --account-name $cosmosName `
  --resource-group $rg `
  --database-name $dbName `
  --name Tarefa `
  --partition-key-path "/email"

# ================================
# Azure Container Registry + Task
# ================================
Write-Host "`nA criar Azure Container Registry '$acrName'..."
az acr create `
  --resource-group $rg `
  --name $acrName `
  --sku Basic `
  --location $location

Write-Host "`nA ativar o acesso administrativo ao ACR..."
az acr update --name $acrName --resource-group $rg --admin-enabled true

az acr task create `
  --registry $acrName `
  --name build-task-gestor-tarefas `
  --image $imageName `
  --context "$gitRepo#$gitBranch:BackEnd" `
  --file "Dockerfile" `
  --platform linux `
  --resource-group $rg `
  --commit-trigger-enabled false `
  --pull-request-trigger-enabled false `
  --base-image-trigger-enabled true

Write-Host "`nA executar build inicial do ACR Task..."
az acr task run --registry $acrName --name build-task-gestor-tarefas --resource-group $rg

# ================================
# Obter credenciais
# ================================
$cosmosEndpoint = az cosmosdb show --name $cosmosName --resource-group $rg --query "documentEndpoint" -o tsv
$cosmosKey = az cosmosdb keys list --name $cosmosName --resource-group $rg --query "primaryMasterKey" -o tsv

$acrUsername = az acr credential show --name $acrName --query username -o tsv
$acrPassword = az acr credential show --name $acrName --query passwords[0].value -o tsv

# ================================
# Container Instance
# ================================
Write-Host "`nA criar Container Instance com imagem '$imageName'..."
az container create `
  --resource-group $rg `
  --name $containerName `
  --image "$acrLoginServer/$imageName" `
  --cpu 1 `
  --memory 1 `
  --registry-login-server $acrLoginServer `
  --registry-username $acrUsername `
  --registry-password $acrPassword `
  --environment-variables `
    PORT=3000 `
    COSMOS_DB_ENDPOINT=$cosmosEndpoint `
    COSMOS_DB_KEY=$cosmosKey `
  --ports 3000 `
  --dns-name-label $dnsLabel `
  --os-type Linux `
  --location $location

# ================================
# Azure Function App + deploy GitHub
# ================================
$storageAccount = "gestortarefasstor202203"
Write-Host "`nA criar Storage Account: $storageAccount..."
az storage account create `
  --name $storageAccount `
  --location $location `
  --resource-group $rg `
  --sku Standard_LRS `
  --kind StorageV2

$functionAppName = "GestorTarefasFunctionApp202203"
Write-Host "`nA criar Function App: $functionAppName..."
az functionapp create `
  --name $functionAppName `
  --resource-group $rg `
  --consumption-plan-location $location `
  --runtime python `
  --runtime-version 3.11 `
  --functions-version 4 `
  --os-type Linux `
  --storage-account $storageAccount `
  --disable-app-insights true

Write-Host "`nA aguardar 60 segundos para a Function App estar pronta..."
Start-Sleep -Seconds 60

$storageConnStr = az storage account show-connection-string --name $storageAccount --resource-group $rg -o tsv
Write-Host "StorageConnStr: $storageConnStr"

az functionapp config appsettings set `
  --name $functionAppName `
  --resource-group $rg `
  --settings `
    "COSMOS_DB_ENDPOINT=$cosmosEndpoint" `
    "COSMOS_DB_KEY=$cosmosKey" `
    "COSMOS_DB_NAME=$dbName" `
    "COSMOS_CONTAINER_NAME=Tarefa" `
    "MAILJET_API_KEY=f1d2c3fa8fbab3a7932d746b28f26257" `
    "MAILJET_SECRET_KEY=b189e2bc3361bc8811c908682627785a" `
    "FUNCTIONS_WORKER_RUNTIME=python" `
    "FUNCTIONS_EXTENSION_VERSION=~4" `
    "AzureWebJobsStorage=$storageConnStr"

# ================================
# Conclusão
# ================================
Write-Host "`nInfraestrutura criada com sucesso."
Write-Host "URL publica do backend: http://$dnsLabel.$location.azurecontainer.io:3000"
Write-Host "Nome do ACR: $acrName"
Write-Host "Nome da Function: $functionAppName"
Write-Host "`nConfigura o GitHub Actions com o secret 'AZURE_FUNCTIONAPP_PUBLISH_PROFILE' para publicar a Function automaticamente."
