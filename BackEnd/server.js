const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const bodyParser = require('body-parser');
const session = require('express-session')

const authRoutes = require('./routes/auth');
const taskRoutes = require('./routes/tarefas');
const uploadRoutes = require('./routes/uploads');

dotenv.config();
const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(bodyParser.json());
    
app.use(session({
    secret: 'amarelo12345', // pode ser definida no .env
    resave: false,
    saveUninitialized: false,
    cookie: {
        maxAge: 1000 * 60 * 60, // 1 hora
        secure: true
    }
}));

app.use('/api/auth',authRoutes);
app.use('/api/tarefas',taskRoutes);
app.use('/api/uploads',uploadRoutes);


app.listen(port, () => {
    console.log(`Server on in port: ${port}`);
})