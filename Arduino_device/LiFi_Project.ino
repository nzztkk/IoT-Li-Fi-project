// Li-Fi Receiver v5
// Исправлено:
// 1. byteStart вычисляется от реального момента первого фронта данных
// 2. blinkError не блокирует прием второго прохода (возврат в loop сразу)
// 3. Метроном второго прохода не теряется

const int LDR_PIN    = A0;
const int LED_GREEN  = 4;
const int LED_RED    = 5;
const int RELAY_PIN  = 12;
const int MOSFET_PIN = 11;

String secretCode = "OPEN!";
int    threshold  = 110;

unsigned long gBitTime = 400;
unsigned long gHalfBit = 200;

unsigned long lastSuccessTime = 0; // Время последнего успешного открытия

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
  pinMode(MOSFET_PIN, OUTPUT);
  pinMode(LED_GREEN,  OUTPUT);
  pinMode(LED_RED,    OUTPUT);
  digitalWrite(LED_RED, HIGH);

  Serial.println("=== Calibrating (no torch!) ===");
  delay(2000);

  long sum = 0;
  for (int i = 0; i < 200; i++) { sum += analogRead(LDR_PIN); delay(10); }
  int ambient = sum / 200;

  threshold = (int)(ambient * 0.6);
  if (threshold < 30)  threshold = 30;
  if (threshold > 600) threshold = 600;

  Serial.print("Ambient: ");    Serial.println(ambient);
  Serial.print("Threshold: <"); Serial.println(threshold);
  Serial.println("=== Ready ===\n");
  digitalWrite(LED_RED, LOW);
}

// ───────── loop ─────────

void loop() {
  if (!isLight()) return;

  // ПРОВЕРКА: Если успех был менее 10 секунд назад, игнорируем второй проход
  if (lastSuccessTime > 0 && (millis() - lastSuccessTime < 10000)) {
    // Просто ждем, пока фонарик погаснет, чтобы не заходить сюда снова сразу
    while(isLight()) { delay(10); } 
    return; 
  }

  Serial.println("[!] Wakeup — waiting for end...");
  digitalWrite(LED_GREEN, HIGH);

  int stable = 0;
  unsigned long ws = millis();
  while (stable < 10) {
    delay(10);
    stable = isDark() ? stable + 1 : 0;
    if (millis() - ws > 8000) {
      Serial.println("Timeout wakeup");
      digitalWrite(LED_GREEN, LOW); return;
    }
  }
  Serial.println("Wakeup end OK.");

  // ───────── МЕТРОНОМ ─────────
  Serial.println("Metronome...");

  if (!waitFor(true,  5000)) { Serial.println("Timeout M1");  digitalWrite(LED_GREEN, LOW); return; }
  unsigned long m1 = millis();
  if (!waitFor(false, 3000)) { Serial.println("Timeout M1f"); digitalWrite(LED_GREEN, LOW); return; }
  if (!waitFor(true,  3000)) { Serial.println("Timeout M2");  digitalWrite(LED_GREEN, LOW); return; }
  unsigned long m2 = millis();
  if (!waitFor(false, 3000)) { Serial.println("Timeout M2f"); digitalWrite(LED_GREEN, LOW); return; }

  gBitTime = m2 - m1;
  gHalfBit = gBitTime / 2;

  Serial.print("-> BIT_TIME: "); Serial.print(gBitTime); Serial.println(" ms");

  if (gBitTime < 200 || gBitTime > 2000) {
    Serial.println("BIT_TIME out of range [200..2000]ms");
    blinkErrorFast(); digitalWrite(LED_GREEN, LOW); return;
  }

  // ───────── СИНХРОНИЗАЦИЯ ─────────
  if (!waitFor(true, 5000)) {
    if (!isLight()) {
      Serial.println("Timeout SYNC");
      blinkErrorFast(); digitalWrite(LED_GREEN, LOW); return;
    }
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
    Serial.println("\n[ERROR] Decoding failed");
    blinkErrorFast();
    digitalWrite(LED_GREEN, LOW);
    return;
  }

  Serial.println("\nResult: [" + msg + "]");
  
  // ───────── ОБРАБОТКА РЕЗУЛЬТАТА ─────────
  if (msg == secretCode) {
    openLock();
    lastSuccessTime = millis(); // ЗАПОМИНАЕМ ВРЕМЯ УСПЕХА
  } else {
    Serial.print("Expected: ["); Serial.print(secretCode); Serial.println("]");
    blinkErrorFast();
  }

  digitalWrite(LED_GREEN, LOW);
  delay(500);
}

// ───────── MANCHESTER DECODER ─────────
//
// byteStart = абсолютный момент начала первого полубита этого байта.
//
// Для каждого бита i:
//   начало первого полубита  = byteStart + i * gBitTime
//   середина первого полубита  = byteStart + i * gBitTime + gHalfBit/4
//   середина второго полубита  = byteStart + i * gBitTime + gHalfBit/4 + gHalfBit
//
// Всё от одного абсолютного начала — дрейф не накапливается.

char readManchesterByte(unsigned long byteStart) {
  byte result = 0;

  for (int i = 0; i < 8; i++) {
    unsigned long tFirst  = byteStart + (unsigned long)i * gBitTime + gHalfBit / 2;
    unsigned long tSecond = tFirst + gHalfBit;

    waitUntil(tFirst);
    int firstHalf = isLight() ? 1 : 0;

    waitUntil(tSecond);
    int secondHalf = isLight() ? 1 : 0;

    if      (firstHalf == 0 && secondHalf == 1) { result |= (1 << (7 - i)); Serial.print("1"); }
    else if (firstHalf == 1 && secondHalf == 0) { Serial.print("0"); }
    else {
      Serial.print("?");
      Serial.print("[i=");   Serial.print(i);
      Serial.print(" f=");   Serial.print(firstHalf);
      Serial.print(" s=");   Serial.print(secondHalf);
      Serial.print(" raw="); Serial.print(readStable());
      Serial.print(" thr="); Serial.print(threshold);
      Serial.print("]");
      return 0;
    }
  }

  Serial.print(" ");
  return (char)result;
}

// ───────── ДЕЙСТВИЯ ─────────

void openLock() {
  Serial.println("!!! ACCESS GRANTED !!!");
  digitalWrite(RELAY_PIN, HIGH);
  delay(100);
  digitalWrite(MOSFET_PIN, HIGH);
  delay(2000);
  digitalWrite(MOSFET_PIN, LOW);
  digitalWrite(RELAY_PIN, LOW);
}

// Быстрое моргание — занимает 600ms вместо 1200ms
// Важно чтобы не пропустить второй проход с iPhone
void blinkErrorFast() {
  Serial.println("WRONG CODE");
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_RED, HIGH); delay(100);
    digitalWrite(LED_RED, LOW);  delay(100);
  }
}
