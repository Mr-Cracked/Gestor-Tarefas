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
    COSMOS_DB_ENDPOINT=$cosmosEndpoint `
    COSMOS_DB_KEY=$cosmosKey `
  --ports 3000 `
  --dns-name-label $dnsLabel `
  --os-type Linux `
  --location $location

# ================================
# Conclusão
# ================================
Write-Host "`nInfraestrutura criada com sucesso."
Write-Host "URL pública do backend: http://$dnsLabel.$location.azurecontainer.io:3000"
Write-Host "Nome do ACR: $acrName"
