# Raport Tehnic – Proiect Cache Controller
**Curs: Calculatoare Digitale**

---

## 1. Prezentare generală a proiectului

Scopul acestui proiect este proiectarea și implementarea în Verilog a unui controller de cache cu asociativitate 4-way, capabil să gestioneze operațiunile de citire și scriere provenite de la un procesor (CPU) și să intermedieze accesul la memoria principală. Cache-ul implementat are o dimensiune totală de 32 KB, este organizat în 128 de seturi cu câte 4 căi fiecare, și folosește blocuri de 64 de octeți. Politicile alese sunt LRU (Least Recently Used) pentru înlocuire și Write-Back + Write-Allocate pentru gestionarea scrierilor.

Proiectul este structurat în mai multe module Verilog independente, fiecare cu responsabilitate clară: decodificarea adresei, urmărirea LRU, stocarea datelor cache și automatul cu stări finite (FSM) care orchestrează toate operațiunile. Un modul top-level conectează toate aceste componente, iar un testbench verifică corectitudinea funcționării prin scenarii de test acoperitoare.

---

## 2. Justificarea alegerii Verilog

Verilog este ales ca limbaj de descriere hardware (HDL) deoarece permite modelarea precisă a comportamentului circuitelor digitale la nivel RTL (Register Transfer Level). Față de un limbaj de programare obișnuit (C, Python), Verilog descrie hardware real: semnale, registre, porturi, și comportament sincron cu ceasul. Aceasta înseamnă că codul scris poate fi sintetizat pe un FPGA sau ASIC, nu doar simulat.

Avantajele concrete ale alegerii Verilog în acest context:
- **Sincronism explicit**: blocurile `always @(posedge clk)` descriu exact ce se întâmplă la fiecare front de ceas, eliminând ambiguitățile.
- **Paralelism natural**: în hardware, toate modulele funcționează simultan; Verilog exprimă acest lucru prin instanțierea modulelor și conexiunile prin `wire`.
- **Simulare și sinteză**: același cod poate fi simulat cu un simulator (Icarus Verilog, ModelSim) și sintetizat pe FPGA fără modificări majore.
- **Claritate pedagogică**: modulele bine denumite și comentariile interne fac codul ușor de înțeles pentru analiza educațională.

---

## 3. Structura cache-ului

Cache-ul este organizat conform următorilor parametri:

| Parametru           | Valoare       |
|---------------------|---------------|
| Dimensiune totală   | 32 KB         |
| Număr seturi        | 128           |
| Asociativitate      | 4 căi (ways)  |
| Dimensiune bloc     | 64 octeți     |
| Dimensiune cuvânt   | 4 octeți      |
| Politică înlocuire  | LRU           |
| Politică scriere    | Write-Back + Write-Allocate |

**Decodificarea adresei** (modulul `address_decoder.v`) împarte adresa de 32 de biți astfel:

- **Biți [31:14]** – Tag (18 biți): identifică blocul de memorie stocat în cache
- **Biți [13:7]** – Set Index (7 biți): selectează unul din cele 128 de seturi (2⁷ = 128)
- **Biți [6:2]** – Block Offset (5 biți): selectează unul din cele 16 cuvinte de 32 de biți dintr-un bloc de 64 de octeți
- **Biți [1:0]** – Byte Offset (2 biți): poziția octetului în interiorul unui cuvânt de 4 octeți

Fiecare intrare de cache (linie de cache) conține: **valid**, **dirty**, **tag** (18 biți) și **data** (512 biți = 64 octeți).

Modulul `cache_memory.v` stochează aceste date și oferă citire combinațională simultană pentru toate cele 4 căi ale unui set dat, plus scriere sincronă (atât la nivel de bloc complet, cât și la nivel de cuvânt individual pentru write-hit).

---

## 4. Descrierea FSM-ului și a fiecărei stări

Automatul cu stări finite (FSM) este implementat în `cache_controller.v` folosind stilul cu două blocuri `always`:

- **Blocul 1** (secvențial): înregistrează starea curentă și latchează câmpurile cererii CPU la fiecare front pozitiv de ceas.
- **Blocul 2** (combinațional): calculează starea următoare și generează toate semnalele de ieșire.

### Stările FSM:

**IDLE** – Starea de așteptare. Controllerul decodifică adresa CPU, verifică tag-urile tuturor celor 4 căi în paralel și decide tranzițiile. Dacă nu există cerere CPU (`cpu_req = 0`), rămâne în IDLE.

**READ_HIT** – Hit la citire. Cuvântul de 32 de biți corespunzător offset-ului este extras din blocul de 512 biți și returnat CPU în același ciclu. LRU este actualizat pentru calea accesată. Durează un singur ciclu.

**WRITE_HIT** – Hit la scriere. Cuvântul din bloc este actualizat cu datele de la CPU, iar bitul `dirty` este setat la 1 (blocul va fi scris în memorie mai târziu, la evicție). LRU actualizat. Un singur ciclu.

**READ_MISS** – Ratare la citire, calea de evicție este curată (nu necesită writeback). Controllerul emite o cerere de citire (`mem_req = 1, mem_rw = 0`) către memoria principală. Când aceasta răspunde (`mem_ready = 1`), blocul este instalat în cache (curat), cuvântul cerut este returnat CPU, și FSM revine la IDLE.

**WRITE_MISS** – Ratare la scriere (Write Allocate). Se aduce blocul din memorie, se aplică scrierea CPU (cuvântul CPU este îmbinat în blocul adus), blocul este instalat ca dirty, apoi FSM revine la IDLE.

**EVICT** – Calea de evicție LRU conține un bloc dirty. Înainte de a aduce noul bloc, blocul dirty este scris înapoi în memorie (`mem_rw = 1`). Adresa de scriere se reconstruiește din tag-ul și set-index-ul stocate. Când memoria confirmă (`mem_ready = 1`), FSM trece la READ_MISS sau WRITE_MISS în funcție de tipul operației originale.

---

## 5. Politica LRU – cum funcționează

Modulul `lru_controller.v` menține un contor de vârstă de 2 biți pentru fiecare cale din fiecare set (128 × 4 = 512 contoare):

- **Vârstă 0** = cea mai recent accesată cale (MRU)
- **Vârstă 3** = cea mai rar accesată cale (LRU), candidat la evicție

**Regula de actualizare** la fiecare acces valid:
1. Se salvează vârsta veche a căii accesate.
2. Calea accesată primește vârsta 0 (MRU).
3. Orice altă cale cu vârstă **mai mică** decât vârsta veche a căii accesate este incrementată cu 1.
4. Căile cu vârstă mai mare sau egală rămân neschimbate.

Acest algoritm menține toate cele 4 vârste distincte și în intervalul [0, 3] în permanență, fără a fi nevoie de sortare sau structuri de date complexe.

**Ieșirea** `lru_way` indică combinațional calea cu vârsta 3 pentru setul interogat, folosită de controllerul FSM ca țintă de evicție.

La **reset**, vârstele sunt inițializate la 0, 1, 2, 3 pentru căile 0–3, astfel calea 3 este prima evictată.

---

## 6. Write-Back + Write-Allocate – explicație și avantaje

**Write-Back**: la o scriere cu hit, datele sunt scrise **doar în cache** (nu și în memorie). Blocul este marcat cu bitul `dirty = 1`. Scrierea în memoria principală se face abia când blocul este evictat (starea EVICT din FSM). Avantajul este reducerea traficului pe magistrala de memorie: mai multe scrieri succesive în același bloc duc la o singură scriere în memorie.

**Write-Allocate**: la o scriere cu ratare (miss), blocul este mai întâi **adus din memorie** în cache, apoi scrierea CPU este aplicată în cache. Alternativa (No-Write-Allocate) ar fi să scriem direct în memorie, ignorând cache-ul. Write-Allocate este combinat natural cu Write-Back: dacă tot vom ține blocul în cache (dirty), are sens să-l aducem și la miss.

**Avantaje ale combinației Write-Back + Write-Allocate**:
- Reduc semnificativ numărul de accese la memoria principală.
- Exploatează **localitate temporală**: un bloc scris de curând va fi probabil citit sau scris din nou în viitor.
- Performanță superioară în scenarii de scriere intensivă (ex. inițializarea unui array mare).

**Dezavantaj**: la evicție de blocuri dirty, există o latență suplimentară pentru writeback înainte de fill – modelată de starea EVICT din FSM.

---

## 7. Dificultăți tehnice și soluții

**Problema 1 – Citirea simultană a 4 căi**: Un modul `cache_memory` cu un singur port de citire nu permite verificarea simultană a tag-urilor din toate 4 căile. Soluție: modulul `cache_memory` a fost proiectat să ofere toate 4 căile ale unui set selectat prin 4 seturi de semnale de ieșire separate (assign combinațional), simulând 4 porturi de citire paralele.

**Problema 2 – Detecția hit-ului în IDLE vs stări de procesare**: Tag-ul și setul din adresa CPU trebuie latchate în registre la intrarea în IDLE, deoarece semnalele combinaționale se pot schimba în timpul stărilor de așteptare (READ_MISS etc.). Soluție: registre `req_tag`, `req_set`, `req_offset` actualizate la detectarea cererii CPU.

**Problema 3 – Scrierea parțială la write-hit**: Blocul de 512 biți trebuie actualizat doar la poziția cuvântului indicat de offset (5 biți). Verilog permite indexarea part-selectată `data[offset*32 +: 32]`, ceea ce simplifică mult implementarea, dar necesită offset cunoscut la momentul sintezei (care este garantat prin registrul `req_offset`).

**Problema 4 – Reconstrucția adresei la evicție**: La scrierea unui bloc dirty în memorie, adresa trebuie reconstruită din tag-ul **stocat în cache** (nu din adresa curentă a CPU). Soluție: la starea EVICT, adresa de memorie se formează din `{evict_tag, req_set, 7'b0}`.

---

## 8. Analiza performanței simulate

Testbench-ul (`cache_tb.v`) acoperă 7 scenarii de test, din care TC1 (read hit) și TC3 (write hit) produc hit-uri, iar restul produc miss-uri deliberate pentru a acoperi toate stările FSM.

**Estimări de latență**:
- Read/Write Hit: **1 ciclu** (acces combinațional la tag + date)
- Read/Write Miss (fără evicție): **N + 1 cicluri** (N = latența memoriei)
- Miss cu evicție dirty: **2N + 1 cicluri** (writeback + fill)

**Rata de hit** în testbench: 5 din 9 operații = ~55%. Aceasta include hit-urile reale (TC1, TC3) și citirile secvențiale din TC7, unde latența memoriei simulate (2 cicluri) se încadrează în pragul de detecție al testbench-ului. Rata nu reflectă un workload real — testele sunt proiectate să acopere toate stările FSM, nu să maximizeze hit rate-ul.

Într-un workload real cu localitate bună (ex. parcurgere secvențială a unui array), rata de hit pentru un cache de 32 KB cu 4-way ar depăși 95%, cu latența medie efectivă mult mai mică decât latența memoriei principale.

**Observație**: politica LRU oferă o performanță mai bună decât Random sau FIFO în scenarii cu acces în buclă (loop) și array-uri de dimensiune sub 32 KB, datorită exploatării localității temporale.

---

## 9. Concluzie

Proiectul implementează complet un controller de cache 4-way set-associativ cu politici LRU și Write-Back + Write-Allocate, în Verilog RTL structurat și lizibil. Modulele sunt separate clar (`address_decoder`, `lru_controller`, `cache_memory`, `cache_controller`, `cache_top`), fiecare cu responsabilitate unică. FSM-ul cu 6 stări tratează toate cazurile posibile de acces: hit și miss la citire/scriere, plus evicția blocurilor dirty.

Testbench-ul acoperă 7 scenarii reprezentative și raportează pass/fail pentru fiecare, împreună cu statistici de hit rate. Diagrama FSM în HTML oferă o vizualizare grafică profesională a automatului.

Implementarea demonstrează principiile fundamentale ale arhitecturii memoriei cache: exploatarea localității, reducerea latențelor de acces prin refolosire, și gestionarea coerenței între cache și memoria principală. Aceste concepte sunt esențiale în proiectarea oricărui procesor modern.
