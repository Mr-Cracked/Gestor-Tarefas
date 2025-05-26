#!/bin/bash

# ================================
# Parametros principais
# ================================
rg="gestorTarefasCN"
location="francecentral"
cosmosName="gestortarefas202203"
dbName="GestorTarefasDB"
containerAppName="gestor-tarefas-backend"
acrName="gestortarefasacr202203"
imageName="gestor-tarefas:latest"
acrLoginServer="$acrName.azurecr.io"
gitRepo="https://github.com/Mr-Cracked/Gestor-Tarefas.git"
gitBranch="main"
storageAccount="gestortarefasstor202203"
functionAppName="GestorTarefasFunctionApp202203"
blobContainer="anexos"
containerAppsEnv="gestor-tarefas-env"

# ================================
# Criar Resource Group
# ================================
echo -e "\nA criar Resource Group: $rg..."
az group create --name "$rg" --location "$location"

# ================================
# Cosmos DB + BD + Containers
# ================================
echo -e "\nA criar conta Cosmos DB: $cosmosName..."
az cosmosdb create \
  --name "$cosmosName" \
  --resource-group "$rg" \
  --locations regionName="$location" failoverPriority=0 \
  --default-consistency-level Session \
  --kind GlobalDocumentDB

echo -e "\nA criar base de dados '$dbName'..."
az cosmosdb sql database create \
  --account-name "$cosmosName" \
  --resource-group "$rg" \
  --name "$dbName"

echo -e "\nA criar container 'Utilizador'..."
az cosmosdb sql container create \
  --account-name "$cosmosName" \
  --resource-group "$rg" \
  --database-name "$dbName" \
  --name Utilizador \
  --partition-key-path "/email"

echo -e "\nA criar container 'Tarefa'..."
az cosmosdb sql container create \
  --account-name "$cosmosName" \
  --resource-group "$rg" \
  --database-name "$dbName" \
  --name Tarefa \
  --partition-key-path "/email"

# ================================
# Azure Container Registry + Task
# ================================
echo -e "\nA criar Azure Container Registry '$acrName'..."
az acr create \
  --resource-group "$rg" \
  --name "$acrName" \
  --sku Basic \
  --location "$location"

echo -e "\nA ativar o acesso administrativo ao ACR..."
az acr update --name "$acrName" --resource-group "$rg" --admin-enabled true

az acr task create \
  --registry "$acrName" \
  --name build-task-gestor-tarefas \
  --image "$imageName" \
  --context "$gitRepo#$gitBranch:BackEnd" \
  --file "Dockerfile" \
  --platform linux \
  --resource-group "$rg" \
  --commit-trigger-enabled false \
  --pull-request-trigger-enabled false \
  --base-image-trigger-enabled true

echo -e "\nA executar build inicial do ACR Task..."
az acr task run --registry "$acrName" --name build-task-gestor-tarefas --resource-group "$rg"

# ================================
# Obter credenciais
# ================================
cosmosEndpoint=$(az cosmosdb show --name "$cosmosName" --resource-group "$rg" --query "documentEndpoint" -o tsv | tr -d '\r')
cosmosKey=$(az cosmosdb keys list --name "$cosmosName" --resource-group "$rg" --query "primaryMasterKey" -o tsv | tr -d '\r')

acrUsername=$(az acr credential show --name "$acrName" --query username -o tsv | tr -d '\r')
acrPassword=$(az acr credential show --name "$acrName" --query passwords[0].value -o tsv | tr -d '\r')

# ================================
# Azure Container Apps Environment
# ================================
echo -e "\nA criar Container Apps Environment: $containerAppsEnv..."
az containerapp env create \
  --name "$containerAppsEnv" \
  --resource-group "$rg" \
  --location "$location"

# ================================
# Azure Container App
# ================================
echo -e "\nA criar Container App com imagem '$imageName'..."
az containerapp create \
  --name "$containerAppName" \
  --resource-group "$rg" \
  --environment "$containerAppsEnv" \
  --image "$acrLoginServer/$imageName" \
  --target-port 3000 \
  --ingress external \
  --registry-server "$acrLoginServer" \
  --registry-username "$acrUsername" \
  --registry-password "$acrPassword" \
  --env-vars \
    PORT=3000 \
    COSMOS_DB_ENDPOINT="$cosmosEndpoint" \
    COSMOS_DB_KEY="$cosmosKey"

# ================================
# Azure Function App
# ================================
echo -e "\nA criar Storage Account: $storageAccount..."
az storage account create \
  --name "$storageAccount" \
  --location "$location" \
  --resource-group "$rg" \
  --sku Standard_LRS \
  --kind StorageV2

echo -e "\nA criar Function App: $functionAppName..."
az functionapp create \
  --name "$functionAppName" \
  --resource-group "$rg" \
  --consumption-plan-location "$location" \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4 \
  --os-type Linux \
  --storage-account "$storageAccount" \
  --disable-app-insights true

# ================================
# Blob Storage - Criar container para anexos
# ================================
echo -e "\nA criar Blob Container: $blobContainer..."
az storage container create \
  --name "$blobContainer" \
  --account-name "$storageAccount" \
  --resource-group "$rg"

# ================================
# Variáveis de ambiente / App Settings
# ================================
storageConnStr=$(az storage account show-connection-string --name "$storageAccount" --resource-group "$rg" -o tsv | tr -d '\r')

echo -e "\nVALORES A USAR:"
echo "COSMOS_DB_ENDPOINT=$cosmosEndpoint"
echo "COSMOS_DB_KEY=$cosmosKey"
echo "AzureWebJobsStorage=$storageConnStr"

az functionapp config appsettings set \
  --name "$functionAppName" \
  --resource-group "$rg" \
  --settings \
    COSMOS_DB_ENDPOINT="$cosmosEndpoint" \
    COSMOS_DB_KEY="$cosmosKey" \
    COSMOS_DB_NAME="$dbName" \
    COSMOS_CONTAINER_NAME=Tarefa \
    MAILJET_API_KEY=f1d2c3fa8fbab3a7932d746b28f26257 \
    MAILJET_SECRET_KEY=b189e2bc3361bc8811c908682627785a \
    FUNCTIONS_WORKER_RUNTIME=python \
    FUNCTIONS_EXTENSION_VERSION=~4 \
    AzureWebJobsStorage="$storageConnStr" \
    AZURE_STORAGE_CONNECTION_STRING="$storageConnStr"

# ================================
# Conclusao
# ================================
containerAppFqdn=$(az containerapp show --name "$containerAppName" --resource-group "$rg" --query "configuration.ingress.fqdn" -o tsv)

echo -e "\nInfraestrutura criada com sucesso."
echo "URL publica do backend: https://$containerAppFqdn"
echo "Nome do ACR: $acrName"
echo "Nome da Function: $functionAppName"
echo "Nome do Blob Container: $blobContainer"
echo "Connection string para Blob Storage adicionada às App Settings (AZURE_STORAGE_CONNECTION_STRING)."
