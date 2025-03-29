const express = require('express');
const bcrypt = require('bcryptjs');
const { CosmosClient } = require('@azure/cosmos');
const dotenv = require('dotenv');
const User = require('../models/Utilizador');

dotenv.config();
const router = express.Router();

// Cosmos DB: ligação à coleção "Users"
const client = new CosmosClient({
    endpoint: process.env.COSMOS_DB_ENDPOINT,
    key: process.env.COSMOS_DB_KEY
});
const database = client.database("GestorTarefasDB");
const container = database.container("Utilizador");

// REGISTO
router.post('/registar', async (req, res) => {
    const { email, password } = req.body;

    try {
        // Verifica se o utilizador já existe
        const { resources: utilizadoresExistentes } = await container.items
            .query({
                query: 'SELECT * FROM c WHERE c.email = @email',
                parameters: [{ name: '@email', value: email }]
            })
            .fetchAll();

        if (utilizadoresExistentes.length > 0) {
            return res.status(400).json({ error: 'Utilizador já existe.' });
        }

        // Cria novo utilizador
        const passwordHash = await bcrypt.hash(password, 10);
        const novoUser = new User(email, passwordHash);

        await container.items.create(novoUser);
        res.status(201).json({ message: 'Utilizador registado com sucesso.' });

    } catch (err) {
        res.status(500).json({ error: 'Erro ao registar utilizador.' });
    }
});

// LOGIN
router.post('/login', async (req, res) => {
    const { email, password } = req.body;

    try {
        // Verifica se o utilizador existe
        const { resources: users } = await container.items
            .query({
                query: 'SELECT * FROM c WHERE c.email = @email',
                parameters: [{ name: '@email', value: email }]
            })
            .fetchAll();

        if (users.length === 0) {
            return res.status(401).json({ error: 'Credenciais inválidas.' });
        }

        const user = users[0];

        // Verifica password
        const passwordMatch = await bcrypt.compare(password, user.passwordHash);
        if (!passwordMatch) {
            return res.status(401).json({ error: 'Credenciais inválidas.' });
        }

        req.session.userEmail = email;

        res.status(200).json({ message: 'Login com sucesso.', email });
    } catch (err) {
        res.status(500).json({ error: 'Erro ao fazer login.' });
        console.log(err)
    }
});

// LOGOUT
router.post('/logout', (req, res) => {
    req.session.destroy(() => {
        res.status(200).json({ message: 'Logout efetuado com sucesso.' });
    });
});


module.exports = router;
