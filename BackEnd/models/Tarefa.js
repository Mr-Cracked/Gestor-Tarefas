class Tarefa {
    constructor(titulo, descricao, prazo, prioridade, estado, anexos, email) {
        this.titulo = titulo;
        this.descricao = descricao;
        this.prazo = prazo;
        this.prioridade = prioridade;
        this.estado = estado;
        this.anexos = anexos;
        this.email = email;
        this.dataCriacao = Date.now();
    }

}

module.exports = Tarefa;