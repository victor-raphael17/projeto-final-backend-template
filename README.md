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

As notificações são geradas automaticamente quando alguém curte um post, comenta ou começa a seguir o usuário. Elas são armazenadas no banco com tipo, dados em JSON e status de leitura. O frontend consulta as notificações via polling (requisições periódicas), sem necessidade de websockets.
