#!/bin/bash

# ================================
# Parametros principais
# ================================
rg="gestorTarefasCN"
location="francecentral"
cosmosName="gestortarefas202203"
dbName="GestorTarefasDB"
containerName="gestor-tarefas-backend"
dnsLabel="gestor-tarefas-api-compnuv"
acrName="gestortarefasacr202203"
imageName="gestor-tarefas:latest"
acrLoginServer="$acrName.azurecr.io"
gitRepo="https://github.com/Mr-Cracked/Gestor-Tarefas.git"
gitBranch="main"
functionAppName="GestorTarefasFunctionApp202203"
storageAccount="gestortarefasstor202203"

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
az cosmosdb sql database create --account-name "$cosmosName" --resource-group "$rg" --name "$dbName"

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
# ACR + Build
# ================================
echo -e "\nA criar Azure Container Registry '$acrName'..."
az acr create --resource-group "$rg" --name "$acrName" --sku Basic --location "$location"
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

acrUsername=$(az acr credential show --name "$acrName" --query username -o tsv)
acrPassword=$(az acr credential show --name "$acrName" --query passwords[0].value -o tsv)

# ================================
# Container Instance
# ================================
echo -e "\nA criar Container Instance com imagem '$imageName'..."
az container create \
  --resource-group "$rg" \
  --name "$containerName" \
  --image "$acrLoginServer/$imageName" \
  --cpu 1 \
  --memory 1 \
  --registry-login-server "$acrLoginServer" \
  --registry-username "$acrUsername" \
  --registry-password "$acrPassword" \
  --environment-variables \
    PORT=3000 \
    COSMOS_DB_ENDPOINT="$cosmosEndpoint" \
    COSMOS_DB_KEY="$cosmosKey" \
  --ports 3000 \
  --dns-name-label "$dnsLabel" \
  --os-type Linux \
  --location "$location"

# ================================
# Function App + Configurar
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

echo -e "\nA aguardar até que a Function App esteja pronta para receber definições..."
for i in {1..15}; do
  state=$(az functionapp show --name "$functionAppName" --resource-group "$rg" --query "state" -o tsv 2>/dev/null)
  if [[ "$state" == "Running" ]]; then
    echo "Function App está ativa."
    break
  fi
  echo "Ainda não está pronta... tentativa $i"
  sleep 10
done

storageConnStr=$(az storage account show-connection-string --name "$storageAccount" --resource-group "$rg" -o tsv | tr -d '\r')

echo -e "\nA configurar variáveis de ambiente..."
az functionapp config appsettings set \
  --name "$functionAppName" \
  --resource-group "$rg" \
  --settings \
    "COSMOS_DB_ENDPOINT=$cosmosEndpoint" \
    "COSMOS_DB_KEY=$cosmosKey" \
    "COSMOS_DB_NAME=$dbName" \
    "COSMOS_CONTAINER_NAME=Tarefa" \
    "MAILJET_API_KEY=f1d2c3fa8fbab3a7932d746b28f26257" \
    "MAILJET_SECRET_KEY=b189e2bc3361bc8811c908682627785a" \
    "FUNCTIONS_WORKER_RUNTIME=python" \
    "FUNCTIONS_EXTENSION_VERSION=~4" \
    "AzureWebJobsStorage=$storageConnStr" \
  --output none \
  && echo "Variáveis configuradas com sucesso." \
  || echo "Erro ao configurar variáveis de ambiente."

# ================================
# Conclusão
# ================================
echo -e "\nInfraestrutura criada com sucesso."
echo "URL publica do backend: http://$dnsLabel.$location.azurecontainer.io:3000"
echo "Nome do ACR: $acrName"
echo "Nome da Function: $functionAppName"
