const express = require('express');
const multer = require('multer');
const { CosmosClient } = require('@azure/cosmos');
const { BlobServiceClient } = require('@azure/storage-blob');
const dotenv = require('dotenv');
const Task = require('../models/Tarefa');

dotenv.config();
const router = express.Router();

// Multer em memória
const storage = multer.memoryStorage();
const upload = multer({ storage });

// Cosmos DB
const client = new CosmosClient({
    endpoint: process.env.COSMOS_DB_ENDPOINT,
    key: process.env.COSMOS_DB_KEY,
});
const database = client.database("GestorTarefasDB");
const container = database.container("Tarefa");

// Blob Storage
const blobServiceClient = BlobServiceClient.fromConnectionString(process.env.AZURE_STORAGE_CONNECTION_STRING);
const blobContainer = 'anexos';
const containerClient = blobServiceClient.getContainerClient(blobContainer);

// Criar nova tarefa + upload anexo
router.post('/criar', upload.single('file'), async (req, res) => {
    const { titulo, descricao, prazo, prioridade, estado } = req.body;
    const file = req.file;
    const email = req.session.userEmail;

    if (!email) return res.status(403).json({ error: 'Não autenticado' });

    let anexoUrl = null;
    if (file) {
        try {
            const blobName = `${Date.now()}-${file.originalname}`;
            const blockBlobClient = containerClient.getBlockBlobClient(blobName);
            await blockBlobClient.uploadData(file.buffer, {
                blobHTTPHeaders: { blobContentType: file.mimetype }
            });
            anexoUrl = blockBlobClient.url;
        } catch (err) {
            return res.status(500).json({ error: 'Erro ao fazer upload do anexo.' });
        }
    }

    try {
        const novaTarefa = new Task(titulo, descricao, prazo, prioridade, estado, anexoUrl ? [anexoUrl] : [], email);
        await container.items.create(novaTarefa);
        res.status(201).json(novaTarefa);
    } catch (err) {
        res.status(500).json({ error: 'Erro ao criar tarefa.' });
        console.log(err);
    }
});

// Listar tarefas do utilizador
router.get('/listar', async (req, res) => {
    const email = req.session.userEmail;
    if (!email) return res.status(403).json({ error: 'Não autenticado' });

    try {
        const { resources: tarefas } = await container.items
            .query({
                query: 'SELECT * FROM Tarefa c WHERE c.email = @email',
                parameters: [{ name: '@email', value: email }]
            })
            .fetchAll();
        res.status(200).json(tarefas);
    } catch (err) {
        res.status(500).json({ error: 'Erro ao listar tarefas.' });
    }
});

// Listar uma tarefa do utilizador
router.get('/listar/:id', async (req, res) => {
    const email = req.session.userEmail;
    const { id } = req.params;
    if (!email) return res.status(403).json({ error: 'Não autenticado' });

    try {
        const { resources: tarefas } = await container.items
            .query({
                query: 'SELECT * FROM Tarefa c WHERE c.id = @id AND c.email = @email',
                parameters: [
                    { name: '@id', value: id },
                    { name: '@email', value: email }
                ]
            })
            .fetchAll();

        if (!tarefas.length) return res.status(404).json({ error: 'Tarefa não encontrada.' });
        res.status(200).json(tarefas[0]);
    } catch (err) {
        res.status(500).json({ error: 'Erro ao listar tarefa.' });
    }
});

// Atualizar tarefa (adicionar/remover anexo opcional)
router.put('/:id', upload.single('file'), async (req, res) => {
    const { id } = req.params;
    const email = req.session.userEmail;
    const { titulo, descricao, prazo, prioridade, estado, removerAnexos = [] } = req.body;
    const file = req.file;

    if (!email) return res.status(403).json({ error: 'Não autenticado' });

    try {
        // Vai buscar a tarefa existente
        const { resource: tarefa } = await container.item(id, email).read();
        if (!tarefa) return res.status(404).json({ error: 'Tarefa não encontrada.' });

        let anexos = tarefa.anexos || [];

        // Remove anexos se pedido
        if (removerAnexos.length) {
            const remover = Array.isArray(removerAnexos) ? removerAnexos : [removerAnexos];
            anexos = anexos.filter(url => !remover.includes(url));
            // Apaga blobs no Storage
            for (const url of remover) {
                const blobName = url.split('/').pop();
                const blockBlobClient = containerClient.getBlockBlobClient(blobName);
                await blockBlobClient.deleteIfExists();
            }
        }

        // Adiciona novo anexo se enviado
        if (file) {
            const blobName = `${Date.now()}-${file.originalname}`;
            const blockBlobClient = containerClient.getBlockBlobClient(blobName);
            await blockBlobClient.uploadData(file.buffer, {
                blobHTTPHeaders: { blobContentType: file.mimetype }
            });
            anexos.push(blockBlobClient.url);
        }

        // Atualiza tarefa
        const updated = {
            ...tarefa,
            titulo: titulo ?? tarefa.titulo,
            descricao: descricao ?? tarefa.descricao,
            prazo: prazo ?? tarefa.prazo,
            prioridade: prioridade ?? tarefa.prioridade,
            estado: estado ?? tarefa.estado,
            anexos,
            id,
            email
        };
        await container.item(id, email).replace(updated);
        res.status(200).json({ message: 'Tarefa atualizada com sucesso.', tarefa: updated });
    } catch (err) {
        res.status(500).json({ error: 'Erro ao atualizar tarefa.' });
    }
});

// Eliminar tarefa (e blobs anexos)
router.delete('/remover/:id', async (req, res) => {
    const { id } = req.params;
    const email = req.session.userEmail;
    if (!email) return res.status(403).json({ error: 'Não autenticado' });

    try {
        // Vai buscar a tarefa para saber os anexos
        const { resource: tarefa } = await container.item(id, email).read();
        if (tarefa && tarefa.anexos && tarefa.anexos.length) {
            for (const url of tarefa.anexos) {
                const blobName = url.split('/').pop();
                const blockBlobClient = containerClient.getBlockBlobClient(blobName);
                await blockBlobClient.deleteIfExists();
            }
        }

        await container.item(id, email).delete();
        res.status(200).json({ message: 'Tarefa removida com sucesso.' });
    } catch (err) {
        res.status(500).json({ error: 'Erro ao remover tarefa.' });
    }
});

module.exports = router;
