// Li-Fi Receiver v6 — ONLY RELAY (Pin 12)
// 1. Убран MOSFET, всё управление на RELAY_PIN (12)
// 2. Оптимизирована логика открытия
// 3. Исправлены тайминги для работы с реле

const int LDR_PIN    = A0;
const int LED_GREEN  = 4;
const int LED_RED    = 5;
const int RELAY_PIN  = 12; // Твое реле на D12

String secretCode = "OPEN!";
int    threshold  = 110;

unsigned long gBitTime = 400;
unsigned long gHalfBit = 200;
unsigned long lastSuccessTime = 0; 

// ───────── утилиты ─────────

int readStable() {
  long s = 0;
  for (int i = 0; i < 3; i++) { s += analogRead(LDR_PIN); delayMicroseconds(300); }
  return s / 3;
}

bool isLight() { return readStable() < threshold; }
bool isDark()  { return !isLight(); }

bool waitFor(bool light, unsigned long timeoutMs) {
  unsigned long t = millis();
  while (light ? isDark() : isLight()) {
    if (millis() - t > timeoutMs) return false;
    delayMicroseconds(300);
  }
  return true;
}

void waitUntil(unsigned long targetMs) {
  while ((long)(targetMs - millis()) > 0) delayMicroseconds(100);
}

// ───────── setup ─────────

void setup() {
  Serial.begin(9600);
  pinMode(RELAY_PIN,  OUTPUT);
  pinMode(LED_GREEN,  OUTPUT);
  pinMode(LED_RED,    OUTPUT);
  
  digitalWrite(RELAY_PIN, LOW); // Гарантируем, что замок закрыт при старте
  digitalWrite(LED_RED, HIGH);

  Serial.println("=== Calibrating ===");
  delay(2000);

  long sum = 0;
  for (int i = 0; i < 200; i++) { sum += analogRead(LDR_PIN); delay(10); }
  int ambient = sum / 200;

  threshold = (int)(ambient * 0.6); // Настройка чувствительности под твой LDR
  if (threshold < 30)  threshold = 30;
  if (threshold > 600) threshold = 600;

  Serial.print("Ambient: ");    Serial.println(ambient);
  Serial.print("Threshold: <"); Serial.println(threshold);
  Serial.println("=== Ready (RELAY ON D12) ===\n");
  digitalWrite(LED_RED, LOW);
}

// ───────── loop ─────────

void loop() {
  if (!isLight()) return;

  // Игнорируем повторные сигналы в течение 10 сек после успеха
  if (lastSuccessTime > 0 && (millis() - lastSuccessTime < 10000)) {
    while(isLight()) { delay(10); } 
    return; 
  }

  Serial.println("[!] Wakeup detected...");
  digitalWrite(LED_GREEN, HIGH);

  int stable = 0;
  unsigned long ws = millis();
  while (stable < 10) {
    delay(10);
    stable = isDark() ? stable + 1 : 0;
    if (millis() - ws > 8000) {
      digitalWrite(LED_GREEN, LOW); return;
    }
  }

  // ───────── МЕТРОНОМ ─────────
  if (!waitFor(true, 5000))  { digitalWrite(LED_GREEN, LOW); return; }
  unsigned long m1 = millis();
  if (!waitFor(false, 3000)) { digitalWrite(LED_GREEN, LOW); return; }
  if (!waitFor(true, 3000))  { digitalWrite(LED_GREEN, LOW); return; }
  unsigned long m2 = millis();
  if (!waitFor(false, 3000)) { digitalWrite(LED_GREEN, LOW); return; }

  gBitTime = m2 - m1;
  gHalfBit = gBitTime / 2;

  if (gBitTime < 200 || gBitTime > 2000) {
    blinkErrorFast(); digitalWrite(LED_GREEN, LOW); return;
  }

  // ───────── СИНХРОНИЗАЦИЯ ─────────
  if (!waitFor(true, 5000)) {
    if (!isLight()) { blinkErrorFast(); digitalWrite(LED_GREEN, LOW); return; }
  }

  unsigned long dataStart = millis();

  // ───────── ЧТЕНИЕ ДАННЫХ ─────────
  bool ok = true;
  String msg = "";

  for (int j = 0; j < (int)secretCode.length() && ok; j++) {
    unsigned long byteStart = dataStart + (unsigned long)j * 8UL * gBitTime;
    char c = readManchesterByte(byteStart);
    if (c == 0) { ok = false; break; }
    msg += c;
  }

  if (!ok) {
    blinkErrorFast();
    digitalWrite(LED_GREEN, LOW);
    return;
  }

  Serial.println("\nReceived: [" + msg + "]");
  
  if (msg == secretCode) {
    openLock();
    lastSuccessTime = millis();
  } else {
    blinkErrorFast();
  }

  digitalWrite(LED_GREEN, LOW);
  delay(500);
}

char readManchesterByte(unsigned long byteStart) {
  byte result = 0;
  for (int i = 0; i < 8; i++) {
    unsigned long tFirst  = byteStart + (unsigned long)i * gBitTime + gHalfBit / 2;
    unsigned long tSecond = tFirst + gHalfBit;

    waitUntil(tFirst);
    int firstHalf = isLight() ? 1 : 0;
    waitUntil(tSecond);
    int secondHalf = isLight() ? 1 : 0;

    if (firstHalf == 0 && secondHalf == 1) { result |= (1 << (7 - i)); Serial.print("1"); }
    else if (firstHalf == 1 && secondHalf == 0) { Serial.print("0"); }
    else { return 0; }
  }
  return (char)result;
}

// ───────── ОТКРЫТИЕ ─────────

void openLock() {
  Serial.println("!!! ACCESS GRANTED !!!");
  
  // Реле щелкает и держит 3 секунды, чтобы ты успел дернуть дверь
  digitalWrite(RELAY_PIN, HIGH);
  delay(3000); 
  digitalWrite(RELAY_PIN, LOW);
  
  Serial.println("Lock closed.");
}

void blinkErrorFast() {
  Serial.println("ACCESS DENIED");
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_RED, HIGH); delay(100);
    digitalWrite(LED_RED, LOW);  delay(100);
  }
}