# ================================
# Parâmetros principais
# ================================
$rg = "gestorTarefasRG"
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
$dockerPath = "BackEnd"

# ================================
# Criar Resource Group
# ================================
Write-Host "`nA criar Resource Group: $rg..."
az group create --name $rg --location $location

# ================================
# Criar conta Cosmos DB
# ================================
Write-Host "`nA criar conta Cosmos DB: $cosmosName..."
az cosmosdb create `
  --name $cosmosName `
  --resource-group $rg `
  --locations regionName=$location failoverPriority=0 `
  --default-consistency-level Session `
  --kind GlobalDocumentDB

# ================================
# Criar base de dados e containers
# ================================
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
# Criar ACR e ativar admin
# ================================
Write-Host "`nA criar Azure Container Registry '$acrName'..."
az acr create `
  --resource-group $rg `
  --name $acrName `
  --sku Basic `
  --location $location

Write-Host "`nA ativar o acesso administrativo ao ACR..."
az acr update --name $acrName --resource-group $rg --admin-enabled true

# ================================
# Criar ACR Task (build automático a partir do GitHub)
# ================================
# Criar ACR Task (build automático a partir do GitHub)
# Criar ACR Task (build automático do GitHub, sem triggers)
az acr task create `
  --registry $acrName `
  --name build-task-gestor-tarefas `
  --image $imageName `
  --context "https://github.com/Mr-Cracked/Gestor-Tarefas.git#main:BackEnd" `
  --file "Dockerfile" `
  --platform linux `
  --resource-group $rg `
  --commit-trigger-enabled false `
  --pull-request-trigger-enabled false `
  --base-image-trigger-enabled true


# ================================
# Executar build inicial manualmente (opcional)
# ================================
Write-Host "`nA executar build inicial do ACR Task..."
az acr task run --registry $acrName --name build-task-gestor-tarefas --resource-group $rg

# ================================
# Obter Cosmos DB credentials
# ================================
$cosmosEndpoint = $(az cosmosdb show --name $cosmosName --resource-group $rg --query "documentEndpoint" -o tsv)
$cosmosKey = $(az cosmosdb keys list --name $cosmosName --resource-group $rg --query "primaryMasterKey" -o tsv)

# ================================
# Obter ACR credentials
# ================================
$acrUsername = $(az acr credential show --name $acrName --query username -o tsv)
$acrPassword = $(az acr credential show --name $acrName --query passwords[0].value -o tsv)

# ================================
# Criar Container Instance
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
# Criar Storage Account para Function App
# ================================
$functionStorage = "gestorfuncstorage$RANDOM"
Write-Host "`nA criar Storage Account para Function App: $functionStorage..."
az storage account create `
  --name $functionStorage `
  --location $location `
  --resource-group $rg `
  --sku Standard_LRS

# ================================
# Criar plano de consumo
# ================================
$functionPlan = "GestorTarefasFuncPlan"
az functionapp plan create `
  --name $functionPlan `
  --resource-group $rg `
  --location $location `
  --number-of-workers 1 `
  --sku Y1 `
  --is-linux

# ================================
# Criar Function App (Python)
# ================================
$functionAppName = "GestorTarefasFunctionApp202203"

Write-Host "`nA criar Function App: $functionAppName..."
az functionapp create `
  --name $functionAppName `
  --storage-account $functionStorage `
  --resource-group $rg `
  --plan $functionPlan `
  --runtime python `
  --runtime-version 3.11 `
  --functions-version 4 `
  --os-type Linux

# ================================
# Configurar variáveis de ambiente da Function
# ================================
Write-Host "`nA configurar variáveis de ambiente da Function App..."
az functionapp config appsettings set `
  --name $functionAppName `
  --resource-group $rg `
  --settings `
    COSMOS_DB_ENDPOINT=$cosmosEndpoint `
    COSMOS_DB_KEY=$cosmosKey `
    COSMOS_DB_NAME=$dbName `
    COSMOS_CONTAINER_NAME="Tarefa" `
    MAILJET_API_KEY="f1d2c3fa8fbab3a7932d746b28f26257" `
    MAILJET_SECRET_KEY="b189e2bc3361bc8811c908682627785a"

# ================================
# Ligar Function App ao GitHub
# ================================
Write-Host "`nA configurar deploy contínuo do GitHub na Function App..."
az functionapp deployment source config `
  --name $functionAppName `
  --resource-group $rg `
  --repo-url $gitRepo `
  --branch $gitBranch `
  --manual-integration `
  --app-working-dir "azure-function-lembrete"



# ================================
# Conclusão
# ================================
Write-Host "`nInfraestrutura criada com sucesso."
Write-Host "URL pública do backend: http://$dnsLabel.$location.azurecontainer.io:3000"
Write-Host "Nome do ACR: $acrName"
Write-Host "Nome da Function: $functionAppName"
