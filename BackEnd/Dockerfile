# Imagem base do Node.js
FROM node:18

# Diretório de trabalho dentro do container
WORKDIR /app

# Copiar os ficheiros de dependências
COPY package*.json ./

# Instalar dependências
RUN npm install

# Copiar o resto do projeto
COPY . .

# Expor a porta usada no teu servidor (ajusta se for diferente)
EXPOSE 3000

# Comando para iniciar o servidor
CMD ["node", "server.js"]
