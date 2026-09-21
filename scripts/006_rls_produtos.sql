-- Supabase expõe as tabelas do schema public numa API REST pública (chave "anon"). Com o RLS ligado
-- e nenhuma policy criada, essa API não lê nem grava nada em produtos.
-- O back-end conecta como o papel "postgres", que ignora o RLS (BYPASSRLS), então continua funcionando.
-- Em um Postgres comum (dev local) o superusuário também ignora o RLS: o script é inofensivo lá.

ALTER TABLE produtos ENABLE ROW LEVEL SECURITY;
