const express = require('express');
const { CosmosClient } = require('@azure/cosmos');
const { BlobServiceClient } = require('@azure/storage-blob');
const dotenv = require('dotenv');
const multer = require('multer');
const Task = require('../models/Tarefa');

dotenv.config();
const router = express.Router();

// Configuração do multer para ficheiros em memória
const storage = multer.memoryStorage();
const upload = multer({ storage });

// Conexão com Cosmos DB
const client = new CosmosClient({
    endpoint: process.env.COSMOS_DB_ENDPOINT,
    key: process.env.COSMOS_DB_KEY,
});
const database = client.database("GestorTarefasDB");
const container = database.container("Tarefa");

// Conexão com Azure Blob Storage
const blobServiceClient = BlobServiceClient.fromConnectionString(process.env.AZURE_STORAGE_CONNECTION_STRING);
const containerName = 'anexos';
const containerClient = blobServiceClient.getContainerClient(containerName);

// Criar nova tarefa (com upload de anexo)
router.post('/criar', upload.single('anexo'), async (req, res) => {
    const { titulo, descricao, prazo, prioridade, estado } = req.body;
    const email = req.session.userEmail;

    if (!email) return res.status(403).json({ error: 'Não autenticado' });

    let anexoUrl = null;
    const file = req.file;

    // Se recebeu ficheiro, faz upload para o Blob Storage
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
        // Podes manter a tua classe Task, mas aqui garanto estrutura JSON
        const novaTarefa = {
            titulo,
            descricao,
            prazo,
            prioridade,
            estado,
            anexos: anexoUrl, // Podes mudar o campo se preferires outro nome
            email
        };
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
                query: 'SELECT * FROM Tarefa c WHERE c.id = @id',
                parameters: [{ name: '@id', value: id }]
            })
            .fetchAll();

        res.status(200).json(tarefas);
    } catch (err) {
        res.status(500).json({ error: 'Erro ao listar tarefas.' });
    }
});

// Atualizar tarefa (podes adaptar para permitir atualizar o anexo)
// Atualizar tarefa, com ou sem novo anexo
router.put('/:id', upload.single('anexo'), async (req, res) => {
    const { id } = req.params;
    const email = req.session.userEmail;
    if (!email) return res.status(403).json({ error: 'Não autenticado' });

    let anexoUrl = req.body.anexos;
    const file = req.file;

    if (file) {
        // (Opcional) Buscar tarefa antiga para obter o URL antigo, para depois apagar do blob
        let tarefaAntiga;
        try {
            const { resources } = await container.items.query({
                query: 'SELECT * FROM Tarefa c WHERE c.id = @id AND c.email = @email',
                parameters: [{ name: '@id', value: id }, { name: '@email', value: email }]
            }).fetchAll();
            tarefaAntiga = resources[0];
        } catch (err) {
            return res.status(500).json({ error: 'Erro ao obter tarefa antiga.' });
        }

        // Upload novo ficheiro
        const blobName = `${Date.now()}-${file.originalname}`;
        const blockBlobClient = containerClient.getBlockBlobClient(blobName);
        await blockBlobClient.uploadData(file.buffer, {
            blobHTTPHeaders: { blobContentType: file.mimetype }
        });
        anexoUrl = blockBlobClient.url;

        // (Opcional) Remover ficheiro antigo do blob
        if (tarefaAntiga && tarefaAntiga.anexos) {
            try {
                const urlParts = tarefaAntiga.anexos.split('/');
                const oldBlobName = urlParts[urlParts.length - 1];
                await containerClient.deleteBlob(oldBlobName);
            } catch (err) {
                console.warn('Não foi possível remover o ficheiro antigo:', err.message);
            }
        }
    }

    try {
        const updated = { ...req.body, id, email, anexos: anexoUrl };
        await container.item(id, email).replace(updated);
        res.status(200).json({ message: 'Tarefa atualizada com sucesso.' });
    } catch (err) {
        res.status(500).json({ error: 'Erro ao atualizar tarefa.' });
    }
});


// Eliminar tarefa
router.delete('/remover/:id', async (req, res) => {
    const { id } = req.params;
    const email = req.session.userEmail;

    if (!email) return res.status(403).json({ error: 'Não autenticado' });

    // Buscar tarefa para obter URL do anexo
    let tarefa;
    try {
        const { resources } = await container.items.query({
            query: 'SELECT * FROM Tarefa c WHERE c.id = @id AND c.email = @email',
            parameters: [{ name: '@id', value: id }, { name: '@email', value: email }]
        }).fetchAll();
        tarefa = resources[0];
    } catch (err) {
        return res.status(500).json({ error: 'Erro ao buscar tarefa.' });
    }

    // Apagar tarefa na BD
    try {
        await container.item(id, email).delete();
    } catch (err) {
        return res.status(500).json({ error: 'Erro ao remover tarefa.' });
    }

    // Apagar ficheiro do Blob Storage, se existir
    if (tarefa && tarefa.anexos) {
        try {
            const urlParts = tarefa.anexos.split('/');
            const blobName = urlParts[urlParts.length - 1];
            await containerClient.deleteBlob(blobName);
        } catch (err) {
            console.warn('Não foi possível remover o anexo:', err.message);
        }
    }

    res.status(200).json({ message: 'Tarefa removida com sucesso.' });
});


module.exports = router;
