#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>

// Credenciais da rede criada pela ESP8266
const char* ssid = "ESP8266_Rede";
const char* password = "12345678";

// Pino do motor
const int PINO_MOTOR = D2;

// Servidor HTTP na porta 80 (servidor só pode ser acessado na rede da esp)
ESP8266WebServer server(80);

// htmlzin cachorro
const char* htmlPage = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
  <title>Controle ESP8266</title>
  <meta charset="UTF-8">
</head>
<body>
  <h1>Controle o Pino D2</h1>
  <form action="/ligar" method="POST">
    <button type="submit">Ligar</button>
  </form>
  <form action="/desligar" method="POST">
    <button type="submit">Desligar</button>
  </form>
</body>
</html>
)rawliteral";

void setup() {
  Serial.begin(115200);
  pinMode(PINO_RELE, OUTPUT);
  digitalWrite(PINO_RELE, LOW); // Garante que comeca desligado

  // Cria a rede wifi
  WiFi.softAP(ssid, password);
  Serial.println("Rede WiFi criada");
  Serial.print("IP address: ");
  Serial.println(WiFi.softAPIP()); // 192.168.4.1 (pode nao ser kkkkk)

  // Pagina principal
  server.on("/", HTTP_GET, []() {
    server.send(200, "text/html", htmlPage);
  });

  // Liga o motor
  server.on("/ligar", HTTP_POST, []() {
    digitalWrite(PINO_MOTOR, HIGH);
    delay(2000);
    digitalWrite(PINO_MOTOR, LOW); // AQUI FALTA IMPLEMENTAR OS LEDS E OS KRL A 4 MAS PACIENCIA
    server.sendHeader("Location", "/");
    server.send(303); // Volta pra pagina principal
  });


  server.begin();
  Serial.println("Servidor HTTP iniciado"); // printa que iniciou pra gente nao ficar perdido
}

void loop() {
  server.handleClient();
}
