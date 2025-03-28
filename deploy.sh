#!/bin/bash

# Nome do resource group
RG_NAME="gestorTarefasCN"
# Localização
LOCATION="francecentral"
# Nome único da conta Cosmos DB
COSMOS_NAME="dbtarefas$(date +%s)"

echo "Criar grupo de recursos: $RG_NAME"
az group create --name $RG_NAME --location $LOCATION

echo "Fazer deploy do Bicep para o grupo: $RG_NAME"
az deployment group create \
  --resource-group $RG_NAME \
  --template-file main.bicep \
  --parameters cosmosDbAccountName=$COSMOS_NAME
