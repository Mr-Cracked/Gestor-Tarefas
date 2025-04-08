import azure.functions as func
import datetime
import os
import logging
from azure.cosmos import CosmosClient
from mailjet_rest import Client

app = func.FunctionApp()

# Corre a cada minuto para testes. Produção: "0 0 8 * * *"
@app.function_name(name="lembrete")
@app.schedule(schedule="*/1 * * * *", arg_name="mytimer", run_on_startup=False, use_monitor=True)
def lembrete_func(mytimer: func.TimerRequest) -> None:
    hoje = datetime.datetime.utcnow().date()

    try:
        # Variáveis de ambiente
        endpoint = os.environ["COSMOS_DB_ENDPOINT"]
        key = os.environ["COSMOS_DB_KEY"]
        db_name = os.environ["COSMOS_DB_NAME"]
        container_name = os.environ["COSMOS_CONTAINER_NAME"]
        mailjet_api_key = os.environ["MAILJET_API_KEY"]
        mailjet_secret = os.environ["MAILJET_SECRET_KEY"]
        remetente = "guilherme.roque@ipcbcampus.pt"

        # Inicializar clientes
        client = CosmosClient(endpoint, credential=key)
        db = client.get_database_client(db_name)
        container = db.get_container_client(container_name)
        mailjet = Client(auth=(mailjet_api_key, mailjet_secret), version='v3.1')

        tarefas = list(container.read_all_items())
        mensagens = []

        for tarefa in tarefas:
            prazo_str = tarefa.get("prazo")
            if not prazo_str:
                continue

            try:
                prazo_data = datetime.datetime.strptime(prazo_str, "%Y-%m-%d").date()
            except ValueError:
                continue

            dias_restantes = (prazo_data - hoje).days

            if 0 <= dias_restantes <= 2:
                email = tarefa.get("email")
                titulo = tarefa.get("titulo") or "Tarefa sem titulo"

                mensagens.append({
                    "From": {
                        "Email": remetente,
                        "Name": "Gestor de Tarefas"
                    },
                    "To": [
                        {
                            "Email": email,
                            "Name": "Utilizador"
                        }
                    ],
                    "Subject": "Lembrete de tarefa proxima do prazo",
                    "HTMLPart": f"<strong>A tarefa '{titulo}' termina em {dias_restantes} dia(s).</strong>"
                })

        if mensagens:
            result = mailjet.send.create(data={"Messages": mensagens})
            if result.status_code == 200:
                logging.info(f"{len(mensagens)} lembretes enviados com sucesso.")
            else:
                logging.warning(f"Erro ao enviar mensagens: {result.status_code} - {result.json()}")
        else:
            logging.info("Nenhum lembrete para enviar hoje.")

    except Exception as e:
        logging.error(f"Erro ao enviar lembretes: {e}")
