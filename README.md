# 📸 InstaClone — Descrição do Projeto

## Visão Geral

O InstaClone é uma rede social inspirada no Instagram, construída como projeto final da disciplina. O objetivo é aplicar todos os conceitos vistos ao longo do curso.

O projeto é dividido em duas partes independentes: o backend (API) e o frontend (interface visual).

## 📐 Especificação completa

Este template inclui três artefatos que, juntos, definem 100% do contrato da API. Quem implementar seguindo todos os três deve produzir um backend byte-for-byte compatível com o frontend de referência:

1. **[`docs/openapi.yaml`](./docs/openapi.yaml)** — contrato OpenAPI 3.0 com todos os endpoints, request/response schemas, status codes e regras de validação visíveis pelo cliente.
2. **[`database/migrations/`](./database/migrations/)** — as 5 migrations customizadas (perfil, follows, posts, likes, comments) com colunas, tipos, índices e foreign keys exatos. As migrations padrão (`users`, `cache`, `jobs`, `personal_access_tokens`) são geradas por `laravel new` + `php artisan install:api`.
3. **[`SPEC.md`](./SPEC.md)** — regras de implementação que OpenAPI e migrations não cobrem: validação `FormRequest`, policies, exceptions customizadas, algoritmos de search/suggestions/feed, comportamento idempotente de follow/like, paths de upload, formato de wrapping `{data: ...}` por recurso, defaults de paginação, e mais.

O README abaixo descreve o **projeto** em alto nível (features, justificativa de cada parte). Para implementar o backend, leia o **OpenAPI primeiro**, depois as **migrations**, depois o **SPEC.md**.

## Backend (API Laravel)

### O que é

Uma API RESTful construída com Laravel que gerencia toda a lógica de uma rede social: usuários, publicações e interações sociais. Os endpoints da API respondem em JSON, serializados por API Resources tipados (`UserResource`, `PostResource`, `CommentResource`), simulando o backend de um aplicativo moderno. O projeto mantém apenas views auxiliares para a página inicial do Laravel e a documentação Swagger UI.

### Autenticação

O sistema utiliza Sanctum para autenticação. O usuário se cadastra, faz login e recebe um token que deve ser enviado em todas as requisições protegidas. A API oferece endpoints para registro, login, logout, renovação de token e consulta do perfil autenticado.

### Usuários e Perfis

Cada usuário possui um perfil consultável por username, com username único, foto de avatar e biografia. O usuário pode editar seu próprio perfil e fazer upload de foto. Há também um endpoint de busca por nome ou username e um endpoint de sugestões de usuários.

### Sistema de Follow

Os usuários podem seguir e deixar de seguir outros perfis. O relacionamento é muitos-para-muitos auto-referencial na tabela de usuários — uma mesma tabela se relaciona consigo mesma. O par seguir/desseguir compartilha a mesma URL (`POST` e `DELETE` em `/api/users/{id}/follow`), e a tentativa de seguir a si mesmo é bloqueada no `FollowService` via `SelfFollowException` (403). A API disponibiliza listagem de seguidores, seguindo e verificação se um usuário segue outro.

### Posts

Os usuários criam publicações com upload de imagem e legenda. Cada post pertence a um único usuário. Apenas o dono do post pode editá-lo ou deletá-lo, o que é garantido pela `PostPolicy`. A API retorna os posts de um usuário específico e também o detalhe individual de cada post.

### Feed

O feed é o coração da rede social. Ele retorna os posts das pessoas que o usuário autenticado segue, ordenados do mais recente para o mais antigo, com paginação. A montagem do feed envolve uma query que cruza a tabela de follows com a tabela de posts, encapsulada em uma camada de serviço própria.

### Curtidas

Os usuários podem curtir e descurtir posts. Cada curtida é um registro único (um usuário só pode curtir um post uma vez). Curtir e descurtir compartilham a mesma URL (`POST` e `DELETE` em `/api/posts/{id}/like`) e o endpoint devolve a contagem atualizada sem exigir um `GET` extra do cliente. A API também expõe a lista de quem curtiu cada post.

### Comentários

Os usuários podem comentar em posts. Cada comentário pertence a um usuário e a um post. Apenas o autor do comentário pode editá-lo ou deletá-lo, o que é garantido pela `CommentPolicy`. Os comentários são listados de forma paginada dentro de cada post.

### Dockerização

O backend é totalmente dockerizado, permitindo subir toda a stack (API + banco) com um único comando. Toda a configuração vive em três pontos: o `Dockerfile`, o `compose.yaml` e o diretório `docker/`.

#### Dockerfile

A imagem da aplicação é construída em um `Dockerfile` multi-stage com dois estágios. O primeiro estágio usa a imagem oficial do Composer para instalar as dependências de produção do PHP (`composer install --no-dev`) com cache de build, copiar o código da aplicação e gerar o autoload otimizado (`composer dump-autoload --classmap-authoritative`). O segundo estágio parte, por padrão, da imagem `dunglas/frankenphp:1-php8.4-alpine`, que já traz o FrankenPHP como servidor web/runtime PHP pronto para produção. Nele são instaladas as extensões necessárias (`pdo_mysql`, `intl`, `zip`, `bcmath`, `opcache`, `pcntl`, `gd`, `redis`), o cliente `mysql-client` (usado pelo entrypoint pra aguardar o banco), o `tini` como init process e o `bash`. O código e o `vendor/` vêm copiados do estágio anterior. A imagem final expõe a porta `8000`, tem `HEALTHCHECK` contra o endpoint `/up` do Laravel e usa o `entrypoint.sh` como ponto de entrada, rodando o FrankenPHP via Caddyfile como comando padrão.

#### compose.yaml

O `compose.yaml` orquestra dois serviços: `mysql` (imagem oficial `mysql:latest`, com database `laravel` e volume nomeado `mysql_data` para persistir os dados) e `app` (build local da aplicação, com `DB_HOST: mysql` pra apontar pro container do banco, variáveis lidas do `.env`, porta `8000` exposta no host e volume `app_storage` montado em `/app/storage` pra preservar uploads e logs entre restarts). O serviço `app` declara `depends_on: mysql`, garantindo a ordem de inicialização.

#### docker/

O diretório `docker/` contém os arquivos auxiliares copiados para dentro da imagem:

- **`docker/entrypoint.sh`** — script que roda antes do FrankenPHP subir. Ele garante que exista um `.env` (copiando do `.env.example` se necessário), gera a `APP_KEY` quando vazia, espera o MySQL ficar pronto via `mysqladmin ping` (com retry de até 60s), roda `php artisan migrate --force` quando `RUN_MIGRATIONS=true`, aplica os caches do Laravel (`config:cache`, `route:cache`, `event:cache`) em produção ou limpa-os em dev, e executa `php artisan storage:link`. No final faz `exec "$@"` pra entregar o controle ao comando do container (FrankenPHP).
- **`docker/php.ini`** — overrides do PHP aplicados via `conf.d/zz-app.ini`: `memory_limit`, limites de upload (`64M`), `max_execution_time`, timezone `UTC` e configurações do OPcache/JIT otimizadas pra produção (`opcache.validate_timestamps=0`, `opcache.jit=1255`, `jit_buffer_size=64M`).

#### Como rodar (primeira execução)

Na primeira vez em que você sobe o projeto numa máquina nova, siga os passos abaixo na ordem. Eles existem por causa de um detalhe de como o Compose lida com `env_file`: variáveis definidas no `.env` entram no container como variáveis de ambiente, e uma `APP_KEY` vazia lá vira uma `APP_KEY` vazia em tempo de execução — o que faz o Laravel estourar `Illuminate\Encryption\MissingAppKeyException` em toda requisição.

**1. Crie o arquivo `.env`**

```bash
cp .env.example .env
```

**2. Gere a `APP_KEY` e grave no `.env`**

A `APP_KEY` do Laravel é só `base64:` seguido de 32 bytes aleatórios — exatamente o que o `php artisan key:generate` faz por baixo dos panos. Como o `vendor/` só existe dentro da imagem (e o entrypoint do container faz um monte de setup antes de qualquer comando rodar), o caminho mais limpo é gerar direto com `openssl` no host:

```bash
sed -i "s|^APP_KEY=.*|APP_KEY=base64:$(openssl rand -base64 32)|" .env
```

Confirme com `grep APP_KEY .env` — deve aparecer algo como `APP_KEY=base64:...`.

**3. Suba a stack**

```bash
docker compose up -d --build
```

Isso builda a imagem, sobe o `mysql` e o `app`, roda as migrations automaticamente no boot (via `entrypoint.sh`) e deixa a API ouvindo em `http://localhost:8000`.

**4. Verifique**

```bash
curl -i http://localhost:8000/up
```

Esperado: `HTTP/1.1 200 OK`. Esse é o healthcheck embutido do Laravel.

#### Mudei o `.env` — e agora?

Importante: `docker compose restart` **não** relê o `env_file`. Ele reaproveita as variáveis de ambiente que o container recebeu na criação. Toda vez que você editar o `.env`, recrie o container:

```bash
docker compose up -d app
```

O Compose detecta a mudança de config e faz `Recreate` no serviço automaticamente. Pra conferir se o valor novo chegou no container, use `docker exec instaclone-backend-app-1 printenv APP_KEY`.
