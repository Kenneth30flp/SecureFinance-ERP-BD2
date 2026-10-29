# Etapa 1: referencia historica

La estructura inicial 50-51 se conserva como base del modulo. La autorizacion
posterior amplio el alcance a recepciones, valoracion e interfaz completa.
El contrato vigente y las instrucciones reemplazan el plan Docker original:
consultar [README.md](README.md).

Etapa 1 introdujo cabecera, detalle inmutable, historial, numeracion identity,
permisos separados, costos de cuatro decimales, aprobador distinto del creador,
idempotencia por UUID y hash, versionado y bloqueos transaccionales.
Las extensiones 52-55 completan ese contrato sin alterar SP compartidos.

No aplicar 50-51 de forma aislada sobre la version final. El instalador debe
aplicar 50-55 completas, ordenadas, dentro de una transaccion. Las pruebas
SQL de etapa 1 siguen incorporadas en ComprasIntegration.js, pero no se han
ejecutado en esta entrega. Los resultados Node estan en RESULTADOS.md.
