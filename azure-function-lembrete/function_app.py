import azure.functions as func
import datetime
import os
import logging
from azure.cosmos import CosmosClient
from mailjet_rest import Client

app = func.FunctionApp()

@app.function_name(name="lembrete")
@app.schedule(schedule="*/1 * * * *", arg_name="mytimer", run_on_startup=False, use_monitor=True)
def lembrete_func(mytimer: func.TimerRequest) -> None:
    hoje = datetime.datetime.utcnow().date()
    dois_dias = hoje + datetime.timedelta(days=2)

    try:
        # Cosmos DB configs
        endpoint = os.environ["COSMOS_DB_ENDPOINT"]
        key = os.environ["COSMOS_DB_KEY"]
        db_name = os.environ["COSMOS_DB_NAME"]
        container_name = os.environ["COSMOS_CONTAINER_NAME"]

        # Mailjet configs
        mailjet_api_key = os.environ["MAILJET_API_KEY"]
        mailjet_secret = os.environ["MAILJET_SECRET_KEY"]
        remetente = "guilherme.roque@ipcbcampus.pt"

        # Inicializar clientes
        client = CosmosClient(endpoint, credential=key)
        db = client.get_database_client(db_name)
        container = db.get_container_client(container_name)

        mailjet = Client(auth=(mailjet_api_key, mailjet_secret), version='v3.1')

        tarefas = list(container.read_all_items())
        lembretes_enviados = 0

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

                titulo = tarefa.get("titulo")

                data = {
                    'Messages': [
                        {
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
                            "Subject": "⏰ Lembrete de tarefa próxima do prazo",
                            "HTMLPart": f"<strong>A tarefa '{titulo}' termina em {dias_restantes} dia(s).</strong>"
                        }
                    ]
                }

                result = mailjet.send.create(data=data)
                if result.status_code == 200:
                    lembretes_enviados += 1
                    logging.info(f"{email} avisado")
                else:
                    logging.warning(f"Erro ao enviar para {email}: {result.status_code} - {result.json()}")

        logging.info(f"{lembretes_enviados} lembretes enviados para tarefas com prazo nos próximos 2 dias")

    except Exception as e:
        logging.error(f"Erro ao enviar lembretes: {e}")
