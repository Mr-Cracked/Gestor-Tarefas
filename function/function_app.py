import azure.functions as func
import datetime
import os
import logging
from azure.cosmos import CosmosClient
from mailjet_rest import Client
from collections import defaultdict

app = func.FunctionApp()

@app.function_name(name="lembrete")
@app.schedule(schedule="*/1 * * * *", arg_name="mytimer", run_on_startup=False, use_monitor=True)
def lembrete_func(mytimer: func.TimerRequest) -> None:
    hoje = datetime.datetime.utcnow().date()

    try:
        # Variaveis de ambiente
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

        # Agrupar tarefas proximas do fim por email
        tarefas_por_email = defaultdict(list)

        for tarefa in tarefas:
            prazo_str = tarefa.get("prazo")
            email = tarefa.get("email")

            if not prazo_str or not email:
                continue

            try:
                prazo_data = datetime.datetime.strptime(prazo_str, "%Y-%m-%d").date()
            except ValueError:
                continue

            dias_restantes = (prazo_data - hoje).days
            if 0 <= dias_restantes <= 2:
                tarefas_por_email[email].append(tarefa)

        mensagens = []

        for email, lista in tarefas_por_email.items():
            total = len(lista)
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
                "Subject": "Lembrete de tarefas proximas do prazo",
                "HTMLPart": f"<strong>Tens {total} tarefa(s) com o prazo proximo do fim.</strong>"
            })

        if mensagens:
            result = mailjet.send.create(data={"Messages": mensagens})
            if result.status_code == 200:
                logging.info(f"{len(mensagens)} mensagens enviadas com sucesso.")
            else:
                logging.warning(f"Erro ao enviar mensagens: {result.status_code} - {result.json()}")
        else:
            logging.info("Nenhuma mensagem a enviar.")

    except Exception as e:
        logging.error(f"Erro na funcao lembrete: {e}")
