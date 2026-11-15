# SeguWatts Vision: luz acesa em cômodo vazio

Proposta para a disciplina **Applied Computer Vision**: detecção de objetos em tempo real com uma YOLO treinada pela equipe.

## A ideia em uma frase

Uma câmera reconhece **lâmpadas e telas ligadas** e **pessoas** no cômodo. Quando há aparelho ligado e ninguém por perto durante um tempo, o SeguWatts registra um evento de desperdício e avisa o morador pelo mesmo fluxo do n8n.

## Por que essa ideia garante a nota

1. **Atende exatamente à rubrica**: detecção de objetos em tempo real e treinamento customizado de uma arquitetura (YOLO) para o problema.
2. **Resolve um limite que a própria equipe documentou.** O README do EcoBot admite que "o LDR não identifica se a luz vem do sol ou de uma lâmpada, nem se há pessoas no cômodo". A visão responde às duas perguntas. Os componentes se encaixam, em vez de existirem como partes soltas, e a banca valoriza isso no 4º ano.
3. **É simples de construir**: 5 classes, dataset fotografado pela própria equipe e treino de cerca de 30 min no Colab gratuito.
4. **Funciona ao vivo no vídeo**: apagar e acender a luz, sair e entrar na frente da câmera. É uma demonstração visual e convincente.
5. **Respeita a LGPD by design**: nenhum quadro é salvo nem enviado, só o evento.

## Classes

| Classe | O que é |
|---|---|
| `lampada_acesa` | Lâmpada, luminária ou abajur emitindo luz |
| `lampada_apagada` | Lâmpada, luminária ou abajur desligado |
| `tela_ligada` | TV ou monitor com imagem |
| `tela_desligada` | TV ou monitor preto |
| `pessoa` | Pessoa no cômodo |

Separar "acesa" de "apagada" e "ligada" de "desligada" é o que torna o treino **customizado de verdade**: o COCO pré-treinado reconhece "tv", mas não sabe se ela está ligada.

## Metodologia passo a passo

1. **Coleta (1 dia).** Cada integrante fotografa a própria casa: cerca de 100 fotos por pessoa, 500 no total. Varie o cômodo, o horário (dia e noite), o ângulo e a distância, com e sem pessoa, com aparelho ligado e desligado. Complete com imagens do [Open Images](https://storage.googleapis.com/openimages/web/index.html) das classes *Lamp* e *Television*, se faltar variedade.
2. **Anotação (1 dia).** No [Roboflow](https://roboflow.com) (gratuito), desenhe as caixas das 5 classes. Divida em 70% treino, 20% validação e 10% teste. Aplique aumentos de dados: brilho ±25%, rotação ±10°, flip horizontal e blur leve. Exporte no formato **YOLOv8/YOLO11**.
3. **Treino (1 hora).** No Google Colab com GPU T4:

   ```python
   !pip install ultralytics roboflow
   from roboflow import Roboflow
   from ultralytics import YOLO

   ds = Roboflow(api_key="SUA_CHAVE").workspace("...").project("seguwatts-vision").version(1).download("yolov8")
   modelo = YOLO("yolo11n.pt")             # transfer learning a partir do COCO
   modelo.train(data=f"{ds.location}/data.yaml", epochs=80, imgsz=640, batch=16, patience=20)
   modelo.val(split="test")                # mAP50, mAP50-95, precisão, recall, matriz de confusão
   ```

   Guarde `runs/detect/train/` inteira: `results.png`, `confusion_matrix.png`, `PR_curve.png` e exemplos de validação vão direto para o PDF.
4. **Tempo real (1 dia).** Script com OpenCV e a webcam (código abaixo): detecção quadro a quadro, suavização temporal e regra de desperdício.
5. **Integração.** O evento é enviado por `POST` ao webhook do n8n, que já decide com IA se vale mandar e-mail ao morador, e é gravado em CSV para o pipeline de dados.
6. **Avaliação.** Reporte o mAP@50 no conjunto de teste (meta ≥ 0,80), a matriz de confusão (o erro mais provável é `tela_desligada` com fundo escuro), o FPS medido na CPU do notebook e 3 casos de erro reais com a explicação de cada um.

## Regra de desperdício (o que transforma detecção em informação)

```text
a cada quadro:
    ligados  = aparelhos detectados como acesa/ligada  (confiança ≥ 0,5)
    presenca = alguma 'pessoa' detectada                (confiança ≥ 0,5)

suavização: um estado só muda se aparecer em ≥ 70% dos quadros da última janela de 2 s
            (evita alerta por piscada ou por um quadro ruim)

se ligados e não presenca por mais de T segundos (120 s; 10 s no modo demonstração):
    emitir evento {cômodo, aparelhos, desde, duração}  → n8n + CSV
    desenhar faixa magenta "Possível desperdício" na tela
quando alguém volta ou o aparelho desliga: encerrar o evento
```

## Esqueleto do detector em tempo real

```python
"""SeguWatts Vision: detector de aparelho ligado em cômodo vazio (webcam)."""
import csv, os, time
from collections import deque
from datetime import datetime

import cv2
import requests
from ultralytics import YOLO

MODELO = YOLO("best.pt")                                  # pesos treinados
WEBHOOK = os.getenv("SEGUWATTS_WEBHOOK_URL")              # webhook do n8n (fora do código)
LIMITE_S = float(os.getenv("LIMITE_SEGUNDOS", "120"))
COMODO = os.getenv("COMODO", "sala")
LIGADOS = {"lampada_acesa", "tela_ligada"}

janela = deque(maxlen=30)                                 # ~2 s de quadros
vazio_desde, evento_aberto = None, False
cam = cv2.VideoCapture(0)

while True:
    ok, quadro = cam.read()
    if not ok:
        break
    r = MODELO(quadro, conf=0.5, verbose=False)[0]
    classes = {r.names[int(c)] for c in r.boxes.cls}
    janela.append((bool(classes & LIGADOS), "pessoa" in classes))

    ligado = sum(l for l, _ in janela) >= 0.7 * len(janela)
    presenca = sum(p for _, p in janela) >= 0.3 * len(janela)
    agora = time.time()

    if ligado and not presenca:
        vazio_desde = vazio_desde or agora
        if agora - vazio_desde >= LIMITE_S and not evento_aberto:
            evento = {"comodo": COMODO, "aparelhos": sorted(classes & LIGADOS),
                      "desde": datetime.fromtimestamp(vazio_desde).isoformat(timespec="seconds")}
            with open("eventos.csv", "a", newline="") as f:
                csv.writer(f).writerow(evento.values())
            if WEBHOOK:
                requests.post(WEBHOOK, json=evento, timeout=5)
            evento_aberto = True
    else:
        vazio_desde, evento_aberto = None, False

    tela = r.plot()
    if evento_aberto:
        cv2.rectangle(tela, (0, 0), (tela.shape[1], 48), (95, 30, 237), -1)
        cv2.putText(tela, "Possivel desperdicio: aparelho ligado sem ninguem",
                    (12, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    cv2.imshow("SeguWatts Vision", tela)
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

cam.release()
cv2.destroyAllWindows()
```

## Estrutura sugerida do repositório

```text
seguwatts-vision/
  README.md              ficha técnica, como rodar, resultados
  dataset/README.md      link do Roboflow, contagem por classe, licença das imagens
  notebooks/treino.ipynb treino no Colab com as saídas salvas
  modelo/best.pt         pesos treinados
  resultados/            results.png, confusion_matrix.png, PR_curve.png, exemplos
  detector.py            tempo real (acima)
  requirements.txt       ultralytics, opencv-python, requests
  docs/relatorio.pdf     documento da disciplina
```

## Entregáveis da disciplina

**PDF (5 pontos):** título; integrantes; resumo (até 250 palavras); introdução (o desperdício invisível e o limite do LDR do EcoBot); objetivo (até 50 palavras); explicação técnica das ferramentas (YOLO11, Ultralytics, Roboflow, OpenCV); metodologia (os 6 passos acima); exemplos de resultados (métricas, matriz de confusão, prints de detecção e de evento); conclusão com limites (sombras, telas com tela de descanso, pessoa fora do enquadramento).

Sugestão de objetivo (48 palavras): *Treinar um modelo YOLO capaz de identificar, em tempo real, lâmpadas e telas ligadas ou desligadas e a presença de pessoas, transformando essas detecções em eventos de possível desperdício de energia, integrados ao fluxo de alertas do SeguWatts, sem armazenar nem transmitir imagens do morador.*

**Vídeo (5 pontos), cerca de 3 minutos:** (1) o problema em 20 s; (2) dataset e treino com as métricas; (3) **demonstração ao vivo**: luz acesa com pessoa → nada; pessoa sai → contador → faixa "Possível desperdício"; pessoa volta → evento encerra; (4) o e-mail chegando pelo n8n; (5) limites e próximos passos.

Quando o repositório estiver pronto, coloque o link em `app/data/projetos.json` (componente `visao`, campo `links`) e mude o `status` para `entregue`. A vitrine atualiza no próximo deploy.
