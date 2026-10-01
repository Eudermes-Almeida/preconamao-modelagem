-- "Família": marcar o celular que parou de receber listas (v1.13.0).
--
-- Sem cadastro, quem apaga o app (ou os dados do navegador) vira outra pessoa para o servidor, e a
-- conexão antiga fica "morta" no celular do outro. O app só afirma isso quando há certeza: o
-- serviço de push (Google/Apple/Mozilla) respondeu que a inscrição de aviso daquele celular não
-- existe mais (404/410) e não sobrou nenhuma outra. Qualquer acesso daquele celular depois disso
-- apaga a marca (ele está vivo).

ALTER TABLE familia_membro ADD COLUMN IF NOT EXISTS app_removido_em TIMESTAMPTZ;
