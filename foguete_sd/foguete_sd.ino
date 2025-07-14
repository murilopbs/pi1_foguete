#include <Wire.h>
#include <Adafruit_ADXL345_U.h>
#include <Adafruit_BMP280.h>
#include <Adafruit_Sensor.h>
#include <BluetoothSerial.h>
#include <ArduinoJson.h>
#include <SD.h>
#include <SPI.h>

// Sensores
Adafruit_ADXL345_Unified accel = Adafruit_ADXL345_Unified(12345);
Adafruit_BMP280 bmp;

// Bluetooth
BluetoothSerial SerialBT;

// SD
#define PIN_SD_CS 5
File logFile;

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

  if (!bmp.begin(0x76)) {
    Serial.println("❌ BMP280 não encontrado!");
    while (1){
      digitalWrite(LED, LOW);
      delay(1000);
      digitalWrite(LED, HIGH);
      delay(1000);
    }
  }

  if (!accel.begin()) {
    Serial.println("❌ ADXL345 não encontrado!");
    while (1){
      digitalWrite(LED, LOW);
      delay(1000);
      digitalWrite(LED, HIGH);
      delay(1000);
    }
  }
  accel.setRange(ADXL345_RANGE_16_G);

  if (!SD.begin(PIN_SD_CS)) {
    Serial.println("❌ Cartão SD não encontrado!");
    while (1){
      digitalWrite(LED, LOW);
      delay(1000);
      digitalWrite(LED, HIGH);
      delay(1000);
    }
  }

  calibrarSensor();
  Serial.println("✅ Sistema pronto. Aguardando lançamento...");
}

void loop() {
  sensors_event_t evento;
  accel.getEvent(&evento);

  float ax = evento.acceleration.x - calibracao.ax;
  float ay = evento.acceleration.y - calibracao.ay;
  float az = evento.acceleration.z - calibracao.az;
  float aTotal = sqrt(ax*ax + ay*ay + az*az);

  switch (estado) {
    case AGUARDANDO_LANCAMENTO: //adicionar estados do led pra todos os cases
      digitalWrite(LED, HIGH);
      Serial.println(aTotal);
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

void iniciarVoo() {
  estado = EM_VOO;
  tempoDecolagem = millis();
  SerialBT.end(); // Desliga o Bluetooth
  Serial.println("LANÇAMENTO DETECTADO!");

  logFile = SD.open("/voo.txt", FILE_WRITE);
  if (logFile) {
    logFile.println("[");
  } else {
    Serial.println("Falha ao abrir o arquivo voo.txt");
  }
}

void monitorarVoo(float aTotal) {
  digitalWrite(LED, LOW);
  String json = gerarJsonDados();

  if (logFile) {
    logFile.println(json + ",");
  }

  Serial.println(json);

  if (aTotal > ACEL_IMPACTO) {
    estado = POUSO_DETECTADO;
    SerialBT.begin("ESP32_Foguete");
    Serial.println("POUSO DETECTADO. Aguardando comando para enviar dados...");

    if (logFile) {
      logFile.seek(logFile.position() - 2); // Remove vírgula da última linha para o json
      logFile.println();
      logFile.println("]");
      logFile.close();
    }
  }

  delay(INTERVALO_COLETA);
  digitalWrite(LED, HIGH);
  delay(INTERVALO_COLETA);
}

void aguardarConexaoBluetooth() {
  if (SerialBT.available() && SerialBT.read() == 'a') {
    enviarDadosDoCartaoSD();
  }
}

String gerarJsonDados() {
  sensors_event_t evento;
  accel.getEvent(&evento);

  StaticJsonDocument<200> doc;
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

  String json;
  serializeJson(doc, json);
  return json;
}

void enviarDadosDoCartaoSD() {
  Serial.println("Enviando dados do voo.txt...");

  File f = SD.open("/voo.txt");
  if (!f) {
    SerialBT.println("{\"erro\": \"voo.txt não encontrado\"}");
    return;
  }

  while (f.available()) {
    String linha = f.readStringUntil('\n');
    linha.trim();
    if (linha.length() == 0) continue;

    SerialBT.println(linha);
    delay(20);
  }

  f.close();
  SerialBT.println("{\"fim\": true}");
  Serial.println("Envio completo.");
}
