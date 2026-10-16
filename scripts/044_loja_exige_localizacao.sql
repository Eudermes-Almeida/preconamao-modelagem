-- =============================================================================================
-- 044 — Trava de localização decidida pela LOJA (pendência B2 do flyer do dono)
-- =============================================================================================
-- Antes: o "Exigir localização" era um botão na tela do cliente, guardado só no aparelho (vinha
-- desligado e o próprio cliente desligava) — não travava nada. Agora a loja decide, no painel
-- /admin (chave geral): com exige_localizacao = true, o app só mostra os preços dela depois do QR
-- code da loja ou da localização dentro do raio. O botão some da tela do cliente (fica só no DES).
-- Padrão false: a loja de demonstração continua aberta em qualquer lugar; a loja parceira liga no
-- dia da instalação (depois de gravar a posição real em /admin/posicao, imprimir os QR codes e
-- testar a 100 m da porta). A trava é no app: a API continua respondendo a quem chamar direto
-- (bloquear a API fica para depois, decisão de 16/10/2026).
-- =============================================================================================

ALTER TABLE loja ADD COLUMN IF NOT EXISTS exige_localizacao BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN loja.exige_localizacao IS
    'true = o app só mostra os preços desta loja a quem leu o QR code dela ou está dentro do raio (B2).';
