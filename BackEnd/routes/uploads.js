const express = require('express');
const multer = require('multer');
const { BlobServiceClient } = require('@azure/storage-blob');
const dotenv = require('dotenv');
const path = require('path');

dotenv.config();
const router = express.Router();

// Configuração do multer
const storage = multer.memoryStorage();
const upload = multer({ storage });

// Azure Blob Storage
//const blobServiceClient = BlobServiceClient.fromConnectionString(process.env.AZURE_STORAGE_CONNECTION_STRING);
const containerName = 'anexos';
//const containerClient = blobServiceClient.getContainerClient(containerName);

// Upload
router.post('/', upload.single('file'), async (req, res) => {
    const file = req.file;
    const email = req.session.userEmail;
    if (!email) return res.status(403).json({ error: 'Não autenticado' });

    if (!file) return res.status(400).json({ error: 'Nenhum ficheiro enviado.' });

    try {
        const blobName = `${Date.now()}-${file.originalname}`;
        const blockBlobClient = containerClient.getBlockBlobClient(blobName);

        await blockBlobClient.uploadData(file.buffer, {
            blobHTTPHeaders: { blobContentType: file.mimetype }
        });

        res.status(201).json({ fileUrl: blockBlobClient.url });
    } catch (err) {
        res.status(500).json({ error: 'Erro ao fazer upload do ficheiro.' });
    }
});

module.exports = router;
