#include <Wire.h>
#include <Adafruit_ADXL345_U.h>
#include <Adafruit_BMP280.h>
#include <Adafruit_Sensor.h>

// Sensores
Adafruit_ADXL345_Unified accel = Adafruit_ADXL345_Unified(12345);
Adafruit_BMP280 bmp; // BMP280, não BME280

// Estados do sistema
bool launchDetected = false;
float initialAltitude = 0;
unsigned long launchTime = 0;

void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22); // ESP32 I2C padrão

  // Inicializa o ADXL345
  if (!accel.begin()) {
    Serial.println("ADXL345 não encontrado!");
    while (1);
  }
  accel.setRange(ADXL345_RANGE_16_G);

  // Inicializa o BMP280
  if (!bmp.begin(0x76)) {
    Serial.println("BMP280 não encontrado!");
    while (1);
  }

  delay(2000); // Estabiliza sensores
  initialAltitude = bmp.readAltitude(1013.25); // Pressão ao nível do mar (ajustável)

  Serial.println("✅ Sistema pronto. Aguardando lançamento...");
}

void loop() {
  // Leitura do acelerômetro
  sensors_event_t accelEvent;
  accel.getEvent(&accelEvent);
  float ax = accelEvent.acceleration.x;
  float ay = accelEvent.acceleration.y;
  float az = accelEvent.acceleration.z;
  float totalAccel = sqrt(ax * ax + ay * ay + az * az);

  // Leitura da altitude
  float altitude = bmp.readAltitude(1013.25);

  if (!launchDetected) {
    if (totalAccel > 2.0) {
      delay(100); // Confirma o pico de aceleração
      float altNow = bmp.readAltitude(1013.25);
      if (altNow - initialAltitude > 1.0) {
        launchDetected = true;
        launchTime = millis();
        Serial.println("🚀 Lançamento detectado!");
      }
    }

    Serial.print("Aguardando... | Accel: ");
    Serial.print(totalAccel);
    Serial.print("g | Alt: ");
    Serial.print(altitude);
    Serial.println(" m");
  } else {
    if(totalAccel < 5){
      launchDetected = false;
    }
    unsigned long elapsed = millis() - launchTime;
    Serial.print("Tempo: ");
    Serial.print(elapsed / 1000.0, 2);
    Serial.print("s | Accel: ");
    Serial.print(totalAccel);
    Serial.print("g | Alt: ");
    Serial.print(altitude);
    Serial.println(" m");
  }

  delay(100);
}
