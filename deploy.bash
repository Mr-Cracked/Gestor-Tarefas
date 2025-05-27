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
functionAppName="GestorTarefasFunctionApp2022033"
blobContainer="anexos"
containerAppsEnv="gestor-tarefas-env"
webappName="gestortarefasfrontend202203"
planName="gestorTarefasPlan"
frontendDir="Gestor-Tarefas/FrontEnd"

# ================================
# Criar Resource Group
# ================================
az group create --name "$rg" --location "$location"

# ================================
# Cosmos DB
# ================================
az cosmosdb create --name "$cosmosName" --resource-group "$rg" --locations regionName="$location" failoverPriority=0 --default-consistency-level Session --kind GlobalDocumentDB
az cosmosdb sql database create --account-name "$cosmosName" --resource-group "$rg" --name "$dbName"
az cosmosdb sql container create --account-name "$cosmosName" --resource-group "$rg" --database-name "$dbName" --name Utilizador --partition-key-path "/email"
az cosmosdb sql container create --account-name "$cosmosName" --resource-group "$rg" --database-name "$dbName" --name Tarefa --partition-key-path "/email"

# ================================
# Azure Container Registry + Build
# ================================
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
az acr task run --registry "$acrName" --name build-task-gestor-tarefas --resource-group "$rg"

# ================================
# Obter credenciais
# ================================
cosmosEndpoint=$(az cosmosdb show --name "$cosmosName" --resource-group "$rg" --query "documentEndpoint" -o tsv)
cosmosKey=$(az cosmosdb keys list --name "$cosmosName" --resource-group "$rg" --query "primaryMasterKey" -o tsv)
acrUsername=$(az acr credential show --name "$acrName" --query username -o tsv)
acrPassword=$(az acr credential show --name "$acrName" --query passwords[0].value -o tsv)

# ================================
# Storage Account + Blob público
# ================================
az storage account create --name "$storageAccount" --location "$location" --resource-group "$rg" --sku Standard_LRS --kind StorageV2

# Ativar acesso público na conta
az storage account update \
  --name "$storageAccount" \
  --resource-group "$rg" \
  --allow-blob-public-access true

# Criar container com acesso público ao blob
az storage container create \
  --name "$blobContainer" \
  --account-name "$storageAccount" \
  --resource-group "$rg" \
  --public-access blob

storageConnStr=$(az storage account show-connection-string --name "$storageAccount" --resource-group "$rg" -o tsv)

# ================================
# Container App
# ================================
az containerapp env create --name "$containerAppsEnv" --resource-group "$rg" --location "$location"
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
  --env-vars PORT=3000 COSMOS_DB_ENDPOINT="$cosmosEndpoint" COSMOS_DB_KEY="$cosmosKey" AZURE_STORAGE_CONNECTION_STRING="$storageConnStr"

# ================================
# Function App
# ================================
gitRepo="https://github.com/Mr-Cracked/Gestor-Tarefas/tree/main/function"

az functionapp create --name "$functionAppName" --resource-group "$rg" --consumption-plan-location "$location" --runtime python --runtime-version 3.11 --functions-version 4 --os-type Linux --storage-account "$storageAccount" --disable-app-insights true
az functionapp config appsettings set \
  --name "$functionAppName" \
  --resource-group "$rg" \
  --repo-url https://github.com/Mr-Cracked/Gestor-Tarefas.git \
  --branch main \
  --manual-integration \
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
# Web App para Frontend
# ================================
az webapp delete --name "$webappName" --resource-group "$rg"
az appservice plan create --name "$planName" --resource-group "$rg" --location "$location" --sku S1
az webapp create --name "$webappName" --resource-group "$rg" --plan "$planName"

# ================================
# Gerar config.js dinâmico
# ================================
backendURL="https://$(az containerapp show --name "$containerAppName" --resource-group "$rg" --query 'configuration.ingress.fqdn' -o tsv)"
echo "window.APP_CONFIG = { API_URL: \"$backendURL\" };" > "$frontendDir/config.js"

# ================================
# Zip e Deploy via curl (sem az webapp deploy)
# ================================
cd "$frontendDir"
zip -r ../../frontend.zip ./*
cd ../..

publishProfile=$(az webapp deployment list-publishing-profiles --name "$webappName" --resource-group "$rg" --output json)
user=$(echo "$publishProfile" | jq -r '.[] | select(.publishMethod=="MSDeploy") | .userName')
pass=$(echo "$publishProfile" | jq -r '.[] | select(.publishMethod=="MSDeploy") | .userPWD')
url=$(echo "$publishProfile" | jq -r '.[] | select(.publishMethod=="MSDeploy") | .publishUrl')

curl -X POST "https://$url/api/zipdeploy" --user "$user:$pass" --data-binary @"./frontend.zip"

# ================================
# Final
# ================================
echo "Infraestrutura criada com sucesso."
echo "URL do backend: $backendURL"
echo "URL do frontend: https://$webappName.azurewebsites.net/login.html"
