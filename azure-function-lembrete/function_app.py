import azure.functions as func
import datetime
import os
import logging
from azure.cosmos import CosmosClient
from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail

app = func.FunctionApp()

@app.function_name(name="lembrete")
@app.schedule(schedule="*/1 * * * *", arg_name="mytimer", run_on_startup=False, use_monitor=True)
def lembrete_func(mytimer: func.TimerRequest) -> None:
    hoje = datetime.datetime.utcnow().date()
    dois_dias = hoje + datetime.timedelta(days=2)
    data_limite = dois_dias.isoformat()

    try:
        endpoint = os.environ["COSMOS_DB_ENDPOINT"]
        key = os.environ["COSMOS_DB_KEY"]
        db_name = os.environ["COSMOS_DB_NAME"]
        container_name = os.environ["COSMOS_CONTAINER_NAME"]
        sendgrid_key = os.environ["SENDGRID_KEY"]

        client = CosmosClient(endpoint, credential=key)
        db = client.get_database_client(db_name)
        container = db.get_container_client(container_name)

        query = "SELECT * FROM c WHERE STARTSWITH(c.prazo, @data)"
        items = list(container.query_items(
            query=query,
            parameters=[{ "name": "@data", "value": data_limite }],
            enable_cross_partition_query=True
        ))

        sg = SendGridAPIClient(sendgrid_key)

        for tarefa in items:
            email = tarefa["email"]
            titulo = tarefa["titulo"]
            msg = Mail(
                from_email="lembrete@gestor.pt",
                to_emails=email,
                subject="⏰ Lembrete de tarefa próxima do prazo",
                html_content=f"<strong>A tarefa '{titulo}' termina em 2 dias.</strong>"
            )
            sg.send(msg)

        logging.info(f"{len(items)} lembretes enviados para {data_limite}")

    except Exception as e:
        logging.error(f"Erro ao enviar lembretes: {e}")
