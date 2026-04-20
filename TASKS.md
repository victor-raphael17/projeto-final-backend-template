# 📸 InstaClone (backend) — Organização de Tasks

## Backend (API Laravel)

### 1 - Setup do Projeto
- [] Criar projeto Laravel
- [] Inicializar repositório Git
- [] Configurar database (MySQL dockerizado)
- [] Configurar .env e .env.example
- [] Criar migrations iniciais (users, password_resets)

### 2 - Autenticação (Sanctum)
- [] Instalar e configurar sanctum
- [] Migration da tabela users
- [] Seeder de usuários fake
- [] POST /api/auth/register
- [] POST /api/auth/login
- [] POST /api/auth/logout
- [] POST /api/auth/refresh
- [] GET /api/auth/me
- [] Middleware de autenticação
- [] AuthService (lógica de negócio separada do controller)

### 3 - Perfil de Usuário
- [] Migration: adicionar campos (username, bio, avatar_url) na tabela users
- [] GET /api/users/{username} — perfil público
- [] PUT /api/users/me — editar próprio perfil
- [] POST /api/users/me/avatar — upload de foto de perfil
- [] GET /api/users/search?q= — buscar usuários
- [] UserService
- [] Configurar storage (local ou S3) pra uploads de imagem

### 4 - Follow
- [] Migration: tabela follows (follower_id, following_id)
- [] Model Follow + relacionamentos no User
- [] POST /api/users/{id}/follow
- [] DELETE /api/users/{id}/unfollow
- [] GET /api/users/{id}/followers
- [] GET /api/users/{id}/following
- [] GET /api/users/{id}/is-following — checar se segue
- [] FollowService
- [] Middleware: impedir de seguir a si mesmo

### 5 - Posts
- [] Migration: tabela posts (user_id, image_url, caption)
- [] Model Post + relacionamentos
- [] POST /api/posts — criar post (upload de imagem + legenda)
- [] GET /api/posts/{id} — detalhe do post
- [] PUT /api/posts/{id} — editar legenda
- [] DELETE /api/posts/{id} — deletar post
- [] GET /api/users/{id}/posts — posts de um usuário
- [] PostService
- [] Middleware: só o dono edita/deleta (policy ou middleware custom)

### 6 - Feed
- [] GET /api/feed — posts de quem o usuário segue, ordenado por data
- [] Paginação com cursor ou offset
- [] FeedService (query otimizada com joins/subqueries)
- [] Incluir contagem de likes e comentários em cada post

### 7 - Curtidas
- [] Migration: tabela likes (user_id, post_id) com unique constraint
- [] Model Like + relacionamentos
- [] POST /api/posts/{id}/like
- [] DELETE /api/posts/{id}/unlike
- [] GET /api/posts/{id}/likes — quem curtiu
- [] LikeService
- [] Toggle: se já curtiu, descurte (ou retorna erro, você escolhe)

### 8 - Comentários
- [] Migration: tabela comments (user_id, post_id, body)
- [] Model Comment + relacionamentos
- [] POST /api/posts/{id}/comments
- [] PUT /api/comments/{id}
- [] DELETE /api/comments/{id}
- [] GET /api/posts/{id}/comments — listagem paginada
- [] CommentService
- [] Middleware: só o dono edita/deleta

### 9 - Notificações
- [] Migration: tabela notifications (user_id, type, data JSON, read_at)
- [] Model Notification
- [] GET /api/notifications — listar notificações do usuário
- [] PUT /api/notifications/read — marcar como lidas
- [] GET /api/notifications/unread-count — contador pra badge
- [] NotificationService
- [] Criar notificação automaticamente ao: curtir, comentar, seguir
  - (pode ser via Observer do Eloquent ou chamada direta na Service)

### 10 - Explorar
- [] GET /api/explore — posts populares (mais curtidas nas últimas 48h)
- [] Excluir posts de quem o usuário já segue
- [] Paginação
- [] ExploreService (query com orderBy na contagem de likes recentes)

### 11 - Finalização
- [] Seeders completos (usuários, posts, follows, likes, comentários)
- [] Testar todos os endpoints (Postman/Insomnia/Curl)
- [] Documentar API (Swagger UI)
- [] Revisar middlewares e policies
- [] Revisar tratamento de erros (try/catch, HTTP status codes corretos)
- [] Configurar CORS pra aceitar requests do frontend