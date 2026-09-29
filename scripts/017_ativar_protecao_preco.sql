-- Liga a proteção de preço da loja piloto: sem sinal de vida do agente há mais de 30 minutos (ou
-- com o PRICETAB da loja diferente do aplicado), o app esconde os preços ("Consulte o preço no
-- terminal da loja") e o AlertaService avisa. Rodar só DEPOIS que o agente fez a primeira carga
-- (loja.hash_aplicado preenchido); senão o app esconde todos os preços.
-- Para desligar (ex.: PC do agente vai ficar desligado): UPDATE loja SET limite_sem_sinal_min = NULL WHERE id = 1;
DO $$
BEGIN
    IF (SELECT hash_aplicado FROM loja WHERE id = 1) IS NULL THEN
        RAISE EXCEPTION 'A loja 1 ainda não recebeu nenhuma carga do agente: instale o agente antes.';
    END IF;
END;
$$;

UPDATE loja SET limite_sem_sinal_min = 30 WHERE id = 1;
