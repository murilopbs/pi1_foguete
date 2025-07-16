#include <Wire.h>
#include <Adafruit_ADXL345_U.h>
#include <Adafruit_BMP280.h>
#include <Adafruit_Sensor.h>
#include <BluetoothSerial.h>
#include <ArduinoJson.h>
#include <SD.h>
#include <SPI.h>
#include <TinyGPSPlus.h>

// Sensores
Adafruit_ADXL345_Unified accel = Adafruit_ADXL345_Unified(12345);
Adafruit_BMP280 bmp;

// Bluetooth
BluetoothSerial SerialBT;

// SD
#define PIN_SD_CS 5
bool sdDisponivel = false;
char nomeArquivo[20] = "/voo.txt"; // nome do arquivo atual

// GPS
HardwareSerial GPS(2); // UART2 (RX=16, TX=17)
TinyGPSPlus gps;

// Enum para o estado do foguete
enum Estado { AGUARDANDO_LANCAMENTO, EM_VOO, POUSO_DETECTADO };
Estado estado = AGUARDANDO_LANCAMENTO;

// LED
#define LED 2

// Parâmetros de detecção
const float ACEL_LANCAMENTO = 15.0;
const float ACEL_IMPACTO = 9.0;
const int INTERVALO_COLETA = 200;

// Tempo
unsigned long tempoDecolagem = 0;

// Struct para a calibração
struct {
  float ax, ay, az;
} calibracao;

void setup() {
  pinMode(LED, OUTPUT);
  Serial.begin(115200);
  SerialBT.begin("ESP32_Foguete");
  digitalWrite(LED, HIGH);

  Wire.begin(21, 22); // I2C ESP32
  GPS.begin(115200, SERIAL_8N1, 16, 17); // GPS RX/TX

  // Inicializa sensores
  if (!bmp.begin(0x76)) {
    Serial.println("❌ BMP280 não encontrado!");
    piscarErro();
  }

  if (!accel.begin()) {
    Serial.println("❌ ADXL345 não encontrado!");
    piscarErro();
  }
  accel.setRange(ADXL345_RANGE_16_G);

  // Inicializa SD Card com tentativas de recuperação
  if (!inicializarSD()) {
    Serial.println("❌ Falha ao inicializar SD Card!");
    piscarErro();
  } else {
    sdDisponivel = true;
    Serial.println("✅ SD Card inicializado com sucesso");
  }

  calibrarSensor();
  Serial.println("✅ Sistema pronto. Aguardando lançamento...");
}

bool inicializarSD() {
  for (int tentativa = 0; tentativa < 3; tentativa++) {
    if (SD.begin(PIN_SD_CS)) {
      return true;
    }
    delay(500);
  }
  return false;
}

void loop() {
  sensors_event_t evento;
  accel.getEvent(&evento);

  float ax = evento.acceleration.x - calibracao.ax;
  float ay = evento.acceleration.y - calibracao.ay;
  float az = evento.acceleration.z - calibracao.az;
  float aTotal = sqrt(ax * ax + ay * ay + az * az);

  while (GPS.available()) {
    gps.encode(GPS.read());
  }

  switch (estado) {
    case AGUARDANDO_LANCAMENTO:
      digitalWrite(LED, HIGH);
      //Serial.println(aTotal);
      if (SerialBT.available() && SerialBT.read() == 'b') {
        enviarDadosTodosOsVoos();
      }
      if (aTotal > ACEL_LANCAMENTO) {
        iniciarVoo();
      }
      break;

    case EM_VOO:
      monitorarVoo(aTotal);
      break;

    case POUSO_DETECTADO:
      aguardarConexaoBluetooth();
      break;
  }

  delay(20);
}

void calibrarSensor() {
  sensors_event_t evento;
  calibracao.ax = calibracao.ay = calibracao.az = 0;

  for (int i = 0; i < 10; i++) {
    accel.getEvent(&evento);
    calibracao.ax += evento.acceleration.x;
    calibracao.ay += evento.acceleration.y;
    calibracao.az += evento.acceleration.z;
    delay(10);
  }

  calibracao.ax /= 10;
  calibracao.ay /= 10;
  calibracao.az /= 10;

  Serial.println("Calibração concluída.");
}

int obterProximoNumeroArquivo() {
  int n = 1;
  char nome[20];

  while (true) {
    sprintf(nome, "/voo%d.txt", n);
    if (!SD.exists(nome)) {
      return n;
    }
    n++;
  }
}

void enviarDadosTodosOsVoos(){
  int n = 2;
  char nome[20];

  while (true){
    sprintf(nome, "/voo%d.txt", n);
    if(!SD.exists(nome)){
      return;
    }
    Serial.println("Enviando dados de " + String(nome));

    if (!sdDisponivel) {
      SerialBT.println("{\"erro\": \"SD Card não disponível\"}");
      return;
    }

    File f = SD.open(nome);
    if (!f) {
      SerialBT.println("{\"erro\": \"Arquivo não encontrado\"}");
      return;
    }

    while (f.available()) {
      String linha = f.readStringUntil('\n');
      linha.trim();
      if (linha.length() == 0) continue;
      if(linha[0] != '[' || linha[0] != ']')
        SerialBT.println(linha);
      delay(5);
    }

    f.close();
    Serial.print("Envio completo: ");
    Serial.println(nome);
    sprintf(nome, "/voo%d.txt", n + 1);
    if(!SD.exists(nome)){
      SerialBT.println("{\"fim\": true}");
      return;
    }else{
      SerialBT.println("{\"fim\": false}");
    }
    n++;
    //return; //depois tirar essa porra
  }
}

void iniciarVoo() {
  estado = EM_VOO;
  tempoDecolagem = millis();
  SerialBT.end(); // Desliga o Bluetooth
  Serial.println("LANÇAMENTO DETECTADO!");

  if (sdDisponivel) {
    int numero = obterProximoNumeroArquivo();
    sprintf(nomeArquivo, "/voo%d.txt", numero);

    File logFile = SD.open(nomeArquivo, FILE_WRITE);
    if (logFile) {
      logFile.println("[");
      logFile.close();
      Serial.println("Arquivo de log iniciado: " + String(nomeArquivo));
    } else {
      Serial.println("Falha ao abrir o arquivo de log");
      sdDisponivel = false;
    }
  }
}

void monitorarVoo(float aTotal) {
  digitalWrite(LED, LOW);
  String json = gerarJsonDados();

  if (sdDisponivel) {
    File logFile = SD.open(nomeArquivo, FILE_APPEND);
    if (logFile) {
      logFile.println(json);
      logFile.close();
    } else {
      Serial.println("Erro ao abrir arquivo para escrita");
      sdDisponivel = false;
    }
  }

  Serial.println(json);

  if (aTotal > ACEL_IMPACTO) {
    estado = POUSO_DETECTADO;
    finalizarGravacao();
    SerialBT.begin("ESP32_Foguete");
    Serial.println("POUSO DETECTADO. Aguardando comando para enviar dados...");
  }

  delay(INTERVALO_COLETA);
  digitalWrite(LED, HIGH);
  delay(INTERVALO_COLETA);
}

void finalizarGravacao() {
  if (sdDisponivel) {
    File logFile = SD.open(nomeArquivo, FILE_APPEND);
    if (logFile) {
      long pos = logFile.position();
      if (pos >= 2) {
        logFile.seek(pos - 2);
      }
      logFile.println();
      logFile.println("]");
      logFile.close();
      Serial.println("Gravação finalizada com sucesso");
    }
  }
}

void aguardarConexaoBluetooth() {
  if (SerialBT.available() && SerialBT.read() == 'a') {
    enviarDadosDoCartaoSD();
    estado = AGUARDANDO_LANCAMENTO;
    Serial.println("Sistema pronto para novo lançamento");
  }
}

String gerarJsonDados() {
  sensors_event_t evento;
  accel.getEvent(&evento);

  StaticJsonDocument<300> doc;
  doc["t"] = millis() - tempoDecolagem;
  doc["ax"] = evento.acceleration.x - calibracao.ax;
  doc["ay"] = evento.acceleration.y - calibracao.ay;
  doc["az"] = evento.acceleration.z - calibracao.az;
  doc["alt"] = bmp.readAltitude(1013.25);
  doc["a"] = sqrt(
    doc["ax"].as<float>() * doc["ax"].as<float>() +
    doc["ay"].as<float>() * doc["ay"].as<float>() +
    doc["az"].as<float>() * doc["az"].as<float>()
  );

  if (gps.location.isValid()) {
    doc["lat"] = gps.location.lat();
    doc["lng"] = gps.location.lng();
  }

  if (gps.altitude.isValid()) {
    doc["gpsAlt"] = gps.altitude.meters();
  }

  if (gps.speed.isValid()) {
    doc["vel"] = gps.speed.kmph();
  }

  String json;
  serializeJson(doc, json);
  return json;
}

void enviarDadosDoCartaoSD() {
  Serial.println("Enviando dados de " + String(nomeArquivo));

  if (!sdDisponivel) {
    SerialBT.println("{\"erro\": \"SD Card não disponível\"}");
    return;
  }

  File f = SD.open(nomeArquivo);
  if (!f) {
    SerialBT.println("{\"erro\": \"Arquivo não encontrado\"}");
    return;
  }

  while (f.available()) {
    String linha = f.readStringUntil('\n');
    linha.trim();
    if (linha.length() == 0) continue;
    SerialBT.println(linha);
    delay(5);
  }

  f.close();
  SerialBT.println("{\"fim\": true}");
  Serial.println("Envio completo.");
}

void piscarErro() {
  while (true) {
    digitalWrite(LED, LOW);
    delay(500);
    digitalWrite(LED, HIGH);
    delay(500);
  }
}
