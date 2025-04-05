# Parâmetros
RG_NAME="gestorTarefasCN"
LOCATION="francecentral"
COSMOS_NAME="gestortarefas20220393"
DB_NAME="GestorTarefasDB"

echo "Faça login..."
az login

echo "A criar Resource Group..."
az group create --name $RG_NAME --location $LOCATION

echo "A criar conta Cosmos DB..."
az cosmosdb create \
  --name $COSMOS_NAME \
  --resource-group $RG_NAME \
  --locations regionName=$LOCATION failoverPriority=0 \
  --default-consistency-level Session \
  --kind GlobalDocumentDB

echo "A criar base de dados '$DB_NAME'..."
az cosmosdb sql database create \
  --account-name $COSMOS_NAME \
  --resource-group $RG_NAME \
  --name $DB_NAME

echo "📁 A criar container 'Users'..."
az cosmosdb sql container create \
  --account-name "$COSMOS_NAME" \
  --resource-group "$RG_NAME" \
  --database-name "$DB_NAME" \
  --name Utilizador \
  --partition-key-path='/email'

echo "📁 A criar container 'Tasks'..."
az cosmosdb sql container create \
  --account-name "$COSMOS_NAME" \
  --resource-group "$RG_NAME" \
  --database-name "$DB_NAME" \
  --name Tarefa \
  --partition-key-path='/email'

echo "Infraestrutura criada com sucesso!"

