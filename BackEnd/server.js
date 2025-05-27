console.log("Starting server...");
console.log("PORT:", process.env.PORT);
console.log("COSMOS_DB_ENDPOINT:", process.env.COSMOS_DB_ENDPOINT);


const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');


const bodyParser = require('body-parser');
const session = require('express-session');

const authRoutes = require('./routes/auth');
const taskRoutes = require('./routes/tarefas');

dotenv.config();
const app = express();
const port = process.env.PORT || 3000;


app.use(cors({
    origin: true,
    credentials: true
}));
app.use(bodyParser.json());

app.use(session({
    secret: 'amarelo12345',
    resave: false,
    saveUninitialized: false,
    cookie: {
        httpOnly: true,
        secure: true,
        sameSite: 'none',
        maxAge: 3600000
    }
}));


app.use('/api/auth',authRoutes);
app.use('/api/tarefas',taskRoutes);

app.listen(port, () => {
    console.log(`Server on in port: ${port}`);
})