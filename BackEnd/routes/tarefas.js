const express = require('express');
const { CosmosClient } = require('@azure/cosmos');
const dotenv = require('dotenv');
const Task = require('../models/Tarefa');

dotenv.config();
const router = express.Router();

// Conexão com Cosmos DB
const client = new CosmosClient({
    endpoint: process.env.COSMOS_DB_ENDPOINT,
    key: process.env.COSMOS_DB_KEY,
});
const database = client.database("GestorTarefasDB");
const container = database.container("Tarefa");


// Criar nova tarefa
router.post('/criar', async (req, res) => {
    const { titulo, descricao, prazo, prioridade, estado, anexos } = req.body;
    const email = req.session.userEmail;

    if (!email) return res.status(403).json({ error: 'Não autenticado' });

    try {
        const novaTarefa = new Task(titulo, descricao, prazo, prioridade, estado, anexos, email);
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

// Atualizar tarefa
router.put('/:id', async (req, res) => {
    const { id } = req.params;
    const email = req.session.userEmail;

    if (!email) return res.status(403).json({ error: 'Não autenticado' });

    try {
        const updated = { ...req.body, id, email };
        await container.item(id, id).replace(updated);
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

    try {
        await container.item(id,email).delete();
        res.status(200).json({ message: 'Tarefa removida com sucesso.' });
    } catch (err) {
        res.status(500).json({ error: 'Erro ao remover tarefa.' });
        console.log(err)
    }
});

module.exports = router;
