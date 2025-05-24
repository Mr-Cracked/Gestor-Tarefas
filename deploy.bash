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
# Storage Account
# ================================
storageAccount="gestortarefasstor202203"
echo -e "\nA criar Storage Account: $storageAccount..."
az storage account create \
  --name "$storageAccount" \
  --location "$location" \
  --resource-group "$rg" \
  --sku Standard_LRS \
  --kind StorageV2


storageConnStr=$(az storage account show-connection-string --name "$storageAccount" --resource-group "$rg" -o tsv | tr -d '\r')
echo "DEBUG - storageConnStr: $storageConnStr"


# ================================
# Container Instance
# ================================

echo "VALORES DAS VARIÁVEIS USADAS NO AZURE CONTAINER:"
echo "-----------------------------------------------"
echo "rg: $rg"
echo "location: $location"
echo "containerName: $containerName"
echo "acrName: $acrName"
echo "imageName: $imageName"
echo "acrLoginServer: $acrLoginServer"
echo "cosmosEndpoint: $cosmosEndpoint"
echo "cosmosKey: $cosmosKey"
echo "storageConnStr: $storageConnStr"
echo "dnsLabel: $dnsLabel"
echo "-----------------------------------------------"

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
    AZURE_STORAGE_CONNECTION_STRING="$storageConnStr" \
  --ports 3000 \
  --dns-name-label "$dnsLabel" \
  --os-type Linux \
  --location "$location"

# ================================
# Azure Function App + deploy GitHub
# ================================


functionAppName="GestorTarefasFunctionApp202203"
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

az functionapp deployment source config \
  --name $functionAppName \
  --resource-group $rg \
  --repo-url $gitRepo \
  --branch $gitBranch \
  --manual-integration



storageConnStr=$(az storage account show-connection-string --name "$storageAccount" --resource-group "$rg" -o tsv | tr -d '\r')

echo -e "\nVALORES A USAR:"
echo "COSMOS_DB_ENDPOINT=$cosmosEndpoint"
echo "COSMOS_DB_KEY=$cosmosKey"
echo "AzureWebJobsStorage=$storageConnStr"

# Configurar variaveis de ambiente na Function App
az functionapp config appsettings set \
  --name "$functionAppName" \
  --resource-group "$rg" \
  --settings \
    COSMOS_DB_ENDPOINT=$cosmosEndpoint \
    COSMOS_DB_KEY=$cosmosKey\
    COSMOS_DB_NAME=$dbName \
    COSMOS_CONTAINER_NAME=Tarefa \
    MAILJET_API_KEY=f1d2c3fa8fbab3a7932d746b28f26257 \
    MAILJET_SECRET_KEY=b189e2bc3361bc8811c908682627785a \
    FUNCTIONS_WORKER_RUNTIME=python \
    FUNCTIONS_EXTENSION_VERSION=~4 \
    AzureWebJobsStorage=$storageConnStr

echo -e "\nA configurar publicação contínua via GitHub para a Function App..."
az functionapp deployment source config \
  --name "$functionAppName" \
  --resource-group "$rg" \
  --repo-url "$gitRepo" \
  --branch "$gitBranch" \
  --manual-integration


# ================================
# Conclusao
# ================================
echo -e "\nInfraestrutura criada com sucesso."
echo "URL publica do backend: http://$dnsLabel.$location.azurecontainer.io:3000"
echo "Nome do ACR: $acrName"
echo "Nome da Function: $functionAppName"
echo -e "\nConfigura o GitHub Actions com o secret 'AZURE_FUNCTIONAPP_PUBLISH_PROFILE' para publicar a Function automaticamente."
