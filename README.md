# Observability Stack

Stack de observabilidade local, pronta para rodar com Docker Compose, para monitorar **métricas** (Prometheus) e **logs** (Loki + Alloy) de uma máquina Linux, com **Grafana** como interface de visualização.

## O que é esse projeto

Este projeto sobe 5 containers que trabalham juntos:

| Serviço | Papel | Porta |
|---|---|---|
| **Prometheus** | Banco de dados de séries temporais. Coleta (faz "scrape") métricas periodicamente. | 9090 |
| **Node Exporter** | Exporta métricas do sistema operacional (CPU, memória, disco, rede) para o Prometheus. | 9100 |
| **Grafana Alloy** | Agente de coleta de logs. Lê o **journal do systemd** da máquina host e envia para o Loki. | 12345 |
| **Loki** | Banco de dados de logs (equivalente ao Prometheus, mas para logs). Recebe os logs enviados pelo Alloy. | 3100 |
| **Grafana** | Dashboard/interface web. Já vem pré-configurado com Prometheus e Loki como fontes de dados (datasources). | 3000 |

Além dos containers, há dois scripts (`scripts/`) que rodam via **cron** na máquina host e geram métricas customizadas:

- `check_pending_updates.sh`: conta quantos pacotes `apt` têm atualização pendente (e quantas são de segurança).
- `check_snap_revisions.sh`: conta quantas revisões antigas de snaps estão acumuladas (candidatas a limpeza).

Esses scripts escrevem arquivos `.prom` na pasta `textfile-collector/`, que é lida pelo **Node Exporter** através do "textfile collector" — assim essas métricas customizadas também aparecem no Prometheus/Grafana como se fossem métricas nativas do sistema.

Resumindo o fluxo de dados:

```
Node Exporter ──┐
                 ├──> Prometheus ──┐
scripts (cron) ──┘                 │
                                    ├──> Grafana (dashboards)
Alloy (journal) ──> Loki ──────────┘
```

## Pré-requisitos

- Linux (o stack lê `/var/log/journal`, `/proc`, `/sys`, então foi pensado para rodar direto na máquina host, não dentro de uma VM isolada sem esses caminhos).
- [Docker](https://docs.docker.com/engine/install/) instalado.
- [Docker Compose](https://docs.docker.com/compose/install/) instalado (`docker compose version` para conferir).
- Permissão para rodar `docker` (usuário no grupo `docker`, ou usar `sudo`).

## Passo a passo para subir os containers

### 1. Clonar o repositório

```bash
git clone https://github.com/Andr3Q/observability-stack.git
cd observability-stack
```

### 2. Conferir os arquivos de configuração

Não é obrigatório mexer em nada para rodar localmente, mas vale entender o que cada arquivo faz antes de subir:

- `docker-compose.yml`: define os 5 serviços, portas e volumes.
- `prometheus.yml`: diz ao Prometheus quais alvos ("targets") ele deve coletar (`localhost:9090` e `node-exporter:9100`).
- `config.alloy`: diz ao Alloy para ler o journal do systemd e mandar para o Loki, adicionando labels `unit` (nome do serviço) e `level` (prioridade do log).
- `grafana-datasources.yml`: provisiona automaticamente o Prometheus e o Loki como datasources no Grafana, para você não ter que cadastrar na mão.

### 3. Subir os containers

Na raiz do projeto, rode:

```bash
docker compose up -d
```

O que acontece aqui:
- O Docker baixa as imagens (`prom/prometheus`, `prom/node-exporter`, `grafana/loki`, `grafana/alloy`, `grafana/grafana`) na primeira execução.
- Os 5 containers são criados e iniciados em segundo plano (`-d` = detached).
- São criados 3 volumes nomeados (`prometheus-data`, `loki-data`, `grafana-data`) para persistir os dados entre reinicializações.

### 4. Conferir se todos os containers subiram corretamente

```bash
docker compose ps
```

Todos os serviços devem aparecer com status `Up` (ou `running`). Se algum não subir, veja os logs dele:

```bash
docker compose logs -f <nome_do_servico>
# exemplo:
docker compose logs -f alloy
```

### 5. Acessar as interfaces

- **Grafana**: http://localhost:3000 (login padrão na primeira vez: usuário `admin`, senha `admin` — ele vai pedir para trocar a senha).
- **Prometheus**: http://localhost:9090 (interface para testar queries PromQL e ver os targets em Status → Targets).
- **Alloy**: http://localhost:12345 (UI de debug do Alloy, mostra o pipeline de coleta de logs rodando).
- **Loki** e **Node Exporter** não têm interface visual própria — são consumidos via Grafana/Prometheus.

### 6. Ver as métricas e os logs no Grafana

1. Entre no Grafana (`http://localhost:3000`).
2. Vá em **Connections → Data sources** e confirme que `Prometheus` e `Loki` já aparecem prontos (foram provisionados automaticamente pelo `grafana-datasources.yml`).
3. Para métricas: **Explore** → selecione o datasource `Prometheus` → rode uma query, por exemplo `node_memory_MemAvailable_bytes` ou `up`.
4. Para logs: **Explore** → selecione o datasource `Loki` → rode uma query, por exemplo `{job="systemd-journal"}`.
5. Opcionalmente, monte um **Dashboard** combinando painéis de métricas e logs.

### 7. Parar / reiniciar / remover os containers

```bash
# Parar os containers (mantém os dados nos volumes)
docker compose stop

# Subir novamente
docker compose start

# Parar e remover os containers (mantém os volumes/dados)
docker compose down

# Parar e remover TUDO, incluindo os dados salvos (irreversível)
docker compose down -v
```

## Métricas customizadas (textfile collector)

O Node Exporter está configurado (`--collector.textfile.directory=/textfile-collector`) para ler qualquer arquivo `.prom` dentro da pasta `textfile-collector/` e expor essas métricas junto com as métricas normais do sistema.

Os arquivos `.prom` são gerados pelos scripts em `scripts/`, que **não rodam dentro de containers** — eles rodam direto na máquina host, agendados via `cron`. Isso é necessário porque `apt` e `snap` são ferramentas do sistema host, não faz sentido rodá-las de dentro de um container.

### Como agendar os scripts (cron)

Dê permissão de execução (já vem definida no repositório, mas caso precise refazer):

```bash
chmod +x scripts/check_pending_updates.sh scripts/check_snap_revisions.sh
```

Edite o crontab do usuário:

```bash
crontab -e
```

E adicione (ajuste o caminho conforme onde você clonou o projeto):

```cron
0 9 * * * /caminho/para/observability-stack/scripts/check_pending_updates.sh
0 9 * * * /caminho/para/observability-stack/scripts/check_snap_revisions.sh
```

Isso roda os dois scripts todo dia às 9h, atualizando os arquivos `.prom`. O Node Exporter relê esses arquivos automaticamente a cada scrape do Prometheus (não precisa reiniciar nada).

As métricas geradas são:

- `pending_updates_total`: total de pacotes com atualização disponível via `apt`.
- `pending_security_updates_total`: quantos desses pacotes são atualizações de segurança.
- `snap_old_revisions_count`: quantas revisões antigas de snaps estão acumuladas no sistema.

> Nota: os arquivos `.prom` gerados (`textfile-collector/*.prom`) não ficam versionados no Git (estão no `.gitignore`), pois são dados que mudam a todo momento — só os scripts que os geram fazem parte do repositório.

## Estrutura do projeto

```
observability-stack/
├── docker-compose.yml          # Orquestração dos 5 containers
├── prometheus.yml               # Configuração de scrape do Prometheus
├── config.alloy                 # Pipeline de coleta de logs do Alloy
├── grafana-datasources.yml      # Provisionamento automático dos datasources no Grafana
├── scripts/
│   ├── check_pending_updates.sh # Gera métrica de atualizações pendentes (apt)
│   └── check_snap_revisions.sh  # Gera métrica de revisões antigas de snap
└── textfile-collector/          # Saída dos scripts, lida pelo Node Exporter (não versionada)
```
