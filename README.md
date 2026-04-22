# 📸 InstaClone — Descrição do Projeto

## Visão Geral

O InstaClone é uma rede social inspirada no Instagram, construída como projeto final da disciplina. O objetivo é aplicar todos os conceitos vistos ao longo do curso.

O projeto é dividido em duas partes independentes: o backend (API) e o frontend (interface visual).

## Backend (API Laravel)

### O que é

Uma API RESTful construída com Laravel que gerencia toda a lógica de uma rede social: usuários, publicações e interações sociais. A API não possui views — toda a comunicação acontece via JSON, simulando o backend de um aplicativo moderno.

### Autenticação

O sistema utiliza Sanctum para autenticação. O usuário se cadastra, faz login e recebe um token que deve ser enviado em todas as requisições protegidas. A API oferece endpoints para registro, login, logout, renovação de token e consulta do perfil autenticado.

### Usuários e Perfis

Cada usuário possui um perfil público com username único, foto de avatar, biografia e contadores de posts, seguidores e seguindo. O usuário pode editar seu próprio perfil e fazer upload de foto. Há também um endpoint de busca para encontrar outros usuários por nome ou username.

### Sistema de Follow

Os usuários podem seguir e deixar de seguir outros perfis. O relacionamento é muitos-para-muitos auto-referencial na tabela de usuários — uma mesma tabela se relaciona consigo mesma. A API disponibiliza listagem de seguidores, seguindo e verificação se um usuário segue outro.

### Posts

Os usuários criam publicações com upload de imagem e legenda. Cada post pertence a um único usuário. Apenas o dono do post pode editá-lo ou deletá-lo, o que é garantido por middlewares e policies. A API retorna os posts de um usuário específico e também o detalhe individual de cada post.

### Feed

O feed é o coração da rede social. Ele retorna os posts das pessoas que o usuário autenticado segue, ordenados do mais recente para o mais antigo, com paginação. A montagem do feed envolve uma query que cruza a tabela de follows com a tabela de posts, encapsulada em uma camada de serviço própria.

### Curtidas

Os usuários podem curtir e descurtir posts. Cada curtida é um registro único (um usuário só pode curtir um post uma vez). A API retorna a contagem de curtidas e a lista de quem curtiu cada post.

### Comentários

Os usuários podem comentar em posts. Cada comentário pertence a um usuário e a um post. Apenas o autor do comentário pode editá-lo ou deletá-lo. Os comentários são listados de forma paginada dentro de cada post.

### Notificações

As notificações são geradas automaticamente quando alguém curte um post, comenta ou começa a seguir o usuário. Elas são armazenadas no banco com tipo, dados em JSON e status de leitura. A API expõe `GET /api/notifications`, `GET /api/notifications/unread-count` e `PUT /api/notifications/read` para consumo futuro — o frontend atual ainda não tem tela dedicada para notificações.

### Dockerização

O backend é totalmente dockerizado, permitindo subir toda a stack (API + banco) com um único comando. Toda a configuração vive em três pontos: o `Dockerfile`, o `compose.yaml` e o diretório `docker/`.

#### Dockerfile

A imagem da aplicação é construída em um `Dockerfile` multi-stage com dois estágios. O primeiro estágio usa a imagem oficial do Composer para instalar as dependências de produção do PHP (`composer install --no-dev`) com cache de build, copiar o código da aplicação e gerar o autoload otimizado (`composer dump-autoload --classmap-authoritative`). O segundo estágio parte da imagem `dunglas/frankenphp:1-php8.3-alpine`, que já traz o FrankenPHP como servidor web/runtime PHP pronto para produção. Nele são instaladas as extensões necessárias (`pdo_mysql`, `intl`, `zip`, `bcmath`, `opcache`, `pcntl`, `gd`, `redis`), o cliente `mysql-client` (usado pelo entrypoint pra aguardar o banco), o `tini` como init process e o `bash`. O código e o `vendor/` vêm copiados do estágio anterior. A imagem final expõe a porta `8000`, tem `HEALTHCHECK` contra o endpoint `/up` do Laravel e usa o `entrypoint.sh` como ponto de entrada, rodando o FrankenPHP via Caddyfile como comando padrão.

#### compose.yaml

O `compose.yaml` orquestra dois serviços: `mysql` (imagem oficial `mysql:latest`, com database `laravel` e volume nomeado `mysql_data` para persistir os dados) e `app` (build local da aplicação, com `DB_HOST: mysql` pra apontar pro container do banco, variáveis lidas do `.env`, porta `8000` exposta no host e volume `app_storage` montado em `/app/storage` pra preservar uploads e logs entre restarts). O serviço `app` declara `depends_on: mysql`, garantindo a ordem de inicialização.

#### docker/

O diretório `docker/` contém os arquivos auxiliares copiados para dentro da imagem:

- **`docker/entrypoint.sh`** — script que roda antes do FrankenPHP subir. Ele garante que exista um `.env` (copiando do `.env.example` se necessário), gera a `APP_KEY` quando vazia, espera o MySQL ficar pronto via `mysqladmin ping` (com retry de até 60s), roda `php artisan migrate --force` quando `RUN_MIGRATIONS=true`, aplica os caches do Laravel (`config:cache`, `route:cache`, `event:cache`) em produção ou limpa-os em dev, e executa `php artisan storage:link`. No final faz `exec "$@"` pra entregar o controle ao comando do container (FrankenPHP).
- **`docker/php.ini`** — overrides do PHP aplicados via `conf.d/zz-app.ini`: `memory_limit`, limites de upload (`64M`), `max_execution_time`, timezone `UTC` e configurações do OPcache/JIT otimizadas pra produção (`opcache.validate_timestamps=0`, `opcache.jit=1255`, `jit_buffer_size=64M`).

#### Como rodar

```bash
docker compose up -d --build
```

A API fica disponível em `http://localhost:8000`. As migrations rodam automaticamente no boot e o storage é persistido em volume.
