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

# Azure Container Registry
acrName="gestortarefasacr202203"
imageName="gestor-tarefas:latest"
acrLoginServer="$acrName.azurecr.io"

# GitHub
gitRepo="https://github.com/Mr-Cracked/Gestor-Tarefas.git"
gitBranch="main"

echo "A criar Resource Group: $rg..."
az group create --name "$rg" --location "$location"

echo "A criar conta Cosmos DB: $cosmosName..."
az cosmosdb create \
  --name "$cosmosName" \
  --resource-group "$rg" \
  --locations regionName="$location" failoverPriority=0 \
  --default-consistency-level Session \
  --kind GlobalDocumentDB

echo "A criar base de dados '$dbName'..."
az cosmosdb sql database create \
  --account-name "$cosmosName" \
  --resource-group "$rg" \
  --name "$dbName"

echo "A criar container 'Utilizador'..."
az cosmosdb sql container create \
  --account-name "$cosmosName" \
  --resource-group "$rg" \
  --database-name "$dbName" \
  --name Utilizador \
  --partition-key-path "/email"

echo "A criar container 'Tarefa'..."
az cosmosdb sql container create \
  --account-name "$cosmosName" \
  --resource-group "$rg" \
  --database-name "$dbName" \
  --name Tarefa \
  --partition-key-path "/email"

echo "A criar Azure Container Registry '$acrName'..."
az acr create \
  --resource-group "$rg" \
  --name "$acrName" \
  --sku Basic \
  --location "$location"

echo "A ativar o acesso administrativo ao ACR..."
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

echo "A executar build inicial do ACR Task..."
az acr task run --registry "$acrName" --name build-task-gestor-tarefas --resource-group "$rg"

cosmosEndpoint=$(az cosmosdb show --name "$cosmosName" --resource-group "$rg" --query "documentEndpoint" -o tsv)
cosmosKey=$(az cosmosdb keys list --name "$cosmosName" --resource-group "$rg" --query "primaryMasterKey" -o tsv)

acrUsername=$(az acr credential show --name "$acrName" --query "username" -o tsv)
acrPassword=$(az acr credential show --name "$acrName" --query "passwords[0].value" -o tsv)

echo "A criar Container Instance com imagem '$imageName'..."
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

storageAccount="gestortarefasstor202203"

echo "A criar Storage Account: $storageAccount..."
az storage account create \
  --name "$storageAccount" \
  --location "$location" \
  --resource-group "$rg" \
  --sku Standard_LRS \
  --kind StorageV2

functionAppName="GestorTarefasFunctionApp202203"

echo "A criar Function App: $functionAppName..."
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

echo "A configurar variaveis de ambiente na Function App..."

cosmosEndpoint=$(az cosmosdb show --name "$cosmosName" --resource-group "$rg" --query "documentEndpoint" -o tsv)
cosmosKey=$(az cosmosdb keys list --name "$cosmosName" --resource-group "$rg" --query "primaryMasterKey" -o tsv)

# Validar os valores
if [[ -z "$cosmosEndpoint" || -z "$cosmosKey" ]]; then
  echo "Erro: Falha ao obter endpoint ou chave da Cosmos DB"
  exit 1
fi

echo "COSMOS_DB_ENDPOINT=$cosmosEndpoint"
echo "COSMOS_DB_KEY=$cosmosKey"

az functionapp config appsettings set \
  --name "$functionAppName" \
  --resource-group "$rg" \
  --settings \
    "COSMOS_DB_ENDPOINT=$cosmosEndpoint" \
    "COSMOS_DB_KEY=$cosmosKey" \
    "COSMOS_DB_NAME=$dbName" \
    "COSMOS_CONTAINER_NAME=Tarefa" \
    "MAILJET_API_KEY=f1d2c3fa8fbab3a7932d746b28f26257" \
    "MAILJET_SECRET_KEY=b189e2bc3361bc8811c908682627785a"

echo "A configurar deploy do GitHub..."
az functionapp deployment source config \
  --name "$functionAppName" \
  --resource-group "$rg" \
  --repo-url "https://github.com/Mr-Cracked/Gestor-Tarefas.git" \
  --branch main \
  --manual-integration \
  --git-token "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"



# ================================
# Conclusao
# ================================

echo "Infraestrutura criada com sucesso."
echo "URL publica do backend: http://$dnsLabel.$location.azurecontainer.io:3000"
echo "Nome do ACR: $acrName"
echo "Nome da Function: $functionAppName"
