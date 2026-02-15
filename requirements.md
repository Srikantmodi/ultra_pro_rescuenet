# RescueNet Pro - Requirements Document (AI-Powered)

## 1. Project Overview

### 1.1 Project Name
**RescueNet Pro** - Edge AI-Powered Mesh Emergency Network

### 1.2 Purpose
RescueNet Pro is an AI-driven offline mesh networking application designed for disaster rescue scenarios. The application leverages **on-device TensorFlow Lite models** for intelligent routing and semantic emergency classification, enabling autonomous emergency communication in environments where traditional infrastructure is unavailable.

### 1.3 Target Platform
- **Primary Platform**: Android (API 29+)
- **Framework**: Flutter 3.10.7+
- **Language**: Dart (Flutter), Kotlin (Android Native)
- **AI Framework**: TensorFlow Lite 2.14.0
- **ML Runtime**: Edge TPU (if available), CPU fallback

### 1.4 Core Value Proposition
- **Edge AI Intelligence**: On-device Deep Q-Network for adaptive mesh routing
- **Semantic Understanding**: NLP model for emergency message classification
- **Zero-Infrastructure**: Operates completely offline using Wi-Fi Direct
- **Predictive Routing**: AI predicts link failures before they occur
- **Smart Triage**: Semantic analysis ensures critical messages get priority

### 1.5 AI Innovation
Unlike traditional rule-based mesh networks, RescueNet Pro employs:
- **Deep Reinforcement Learning** for routing decisions (DQN architecture)
- **Natural Language Processing** for emergency severity classification (LSTM/MobileBERT)
- **Predictive Analytics** for link stability forecasting
- **Adaptive Learning** that improves with network usage

---

## 2. Functional Requirements

### 2.1 User Roles

#### 2.1.1 Sender (I Need Help)
- **FR-1.1**: User can create and send emergency SOS alerts
- **FR-1.2**: User can type free-form emergency message (NLP analyzed)
- **FR-1.3**: **AI automatically classifies severity** using TFLite NLP model (Critical/Warning/General)
- **FR-1.4**: AI provides real-time message urgency feedback
- **FR-1.5**: User can provide personal information (name, contact)
- **FR-1.6**: User can select medical conditions from predefined list
- **FR-1.7**: System automatically captures GPS location with accuracy
- **FR-1.8**: User can view nearby mesh nodes with **AI-predicted link stability scores**
- **FR-1.9**: **AI selects optimal relay node** using Deep Q-Network

#### 2.1.2 Responder (I Can Help)
- **FR-2.1**: User can view incoming SOS alerts **sorted by AI-predicted urgency**
- **FR-2.2**: User can see AI confidence scores for urgency classification
- **FR-2.3**: User can view SOS alerts on an interactive map
- **FR-2.4**: AI automatically filters spam/non-emergency messages
- **FR-2.5**: User can acknowledge receipt of SOS alerts
- **FR-2.6**: User can view AI-generated emergency summaries

#### 2.1.3 Relay Node
- **FR-3.1**: **AI autonomously manages packet forwarding** without user intervention
- **FR-3.2**: System runs as foreground service with edge AI inference
- **FR-3.3**: Device broadcasts AI-computed availability metrics
- **FR-3.4**: System displays **AI routing statistics** (success rate, predicted failures avoided)
- **FR-3.5**: User can view **real-time AI decision explanations**
- **FR-3.6**: **AI optimizes battery usage** by predicting idle periods

### 2.2 AI-Powered Mesh Network Operations

#### 2.2.1 Intelligent Device Discovery
- **FR-4.1**: System discovers nearby devices using Wi-Fi Direct DNS-SD
- **FR-4.2**: **AI analyzes discovery patterns** to optimize refresh intervals (8-20s adaptive)
- **FR-4.3**: System broadcasts AI-enriched metadata (battery trend, predicted uptime, link quality)
- **FR-4.4**: **AI filters unstable devices** based on RSSI volatility
- **FR-4.5**: **Predictive stale device detection** using time-series analysis

#### 2.2.2 AI-Driven Packet Routing (Deep Q-Network)
- **FR-5.1**: **TensorFlow Lite DQN model** makes routing decisions (<50ms latency)
- **FR-5.2**: **AI Input Features**:
  - RSSI Trend (not just current value): 5-second moving average and variance
  - Battery Level & Discharge Rate: Predicts remaining relay capacity
  - Queue Congestion: Number of pending packets at neighbor
  - Historical Success Rate: Per-link delivery statistics
  - Link Age: How long the connection has been stable
- **FR-5.3**: **AI Output**: Link Stability Score (0.0 to 1.0) for each neighbor
- **FR-5.4**: **Predictive Rerouting**: AI reroutes BEFORE link fails (proactive)
- **FR-5.5**: System prevents routing loops using packet trace + AI cycle detection
- **FR-5.6**: **AI-prioritized retries**: Model predicts optimal retry timing
- **FR-5.7**: **Dynamic TTL**: AI adjusts packet TTL based on network density (5-15 hops)

#### 2.2.3 Semantic Emergency Classification (NLP)
- **FR-6.1**: **TFLite NLP model** classifies emergency messages in real-time
- **FR-6.2**: **Model Architecture**: Quantized MobileBERT (8-bit) or LSTM (2-layer, 128 units)
- **FR-6.3**: **Training Data**: 50K+ disaster-related messages (multi-language)
- **FR-6.4**: **Classification Categories**:
  - **CRITICAL (P1)**: Life-threatening keywords (bleeding, fire, trapped, drowning, heart attack)
  - **WARNING (P2)**: Urgent needs (water, food, medical supplies, shelter)
  - **GENERAL (P3)**: Status updates (safe, relocating, checking in)
- **FR-6.5**: **Confidence Scoring**: Model provides 0-100% confidence for each class
- **FR-6.6**: **Multi-language Support**: Model trained on English, Hindi, Tamil, Telugu
- **FR-6.7**: **Semantic Similarity**: AI groups related emergencies automatically

#### 2.2.4 AI-Enhanced Packet Management
- **FR-7.1**: Each packet includes AI metadata (predicted urgency, routing score)
- **FR-7.2**: **AI deduplication**: Semantic similarity check (not just ID match)
- **FR-7.3**: **Smart caching**: AI predicts which packets to cache based on network state
- **FR-7.4**: **Adaptive outbox**: AI adjusts queue size based on network load
- **FR-7.5**: **Packet expiry prediction**: AI estimates delivery probability

#### 2.2.5 Connection Management
- **FR-8.1**: System establishes Wi-Fi Direct connections on-demand
- **FR-8.2**: **AI connection timeout**: Model predicts optimal timeout per peer
- **FR-8.3**: Socket communication on port 8888
- **FR-8.4**: **AI failure detection**: Model predicts connection failures 2-3s early
- **FR-8.5**: **Smart cleanup**: AI determines when to close connections

### 2.3 AI Training & Inference

#### 2.3.1 Model Training (Offline)
- **FR-9.1**: DQN model trained on simulated mesh network scenarios (1M+ episodes)
- **FR-9.2**: NLP model trained on labeled emergency message dataset (50K+ samples)
- **FR-9.3**: Models quantized to 8-bit for mobile deployment (<5MB size)
- **FR-9.4**: Transfer learning from pre-trained BERT for NLP
- **FR-9.5**: Reinforcement learning with reward shaping for routing

#### 2.3.2 On-Device Inference
- **FR-10.1**: TFLite inference runs on-device (no cloud dependency)
- **FR-10.2**: DQN inference: <50ms per routing decision
- **FR-10.3**: NLP inference: <100ms per message classification
- **FR-10.4**: **Edge TPU acceleration** when available (Google Pixel, Samsung flagships)
- **FR-10.5**: **Fallback to CPU** with NNAPI optimization
- **FR-10.6**: Model caching: Models loaded once at app start

#### 2.3.3 Adaptive Learning (Future)
- **FR-11.1**: On-device experience replay buffer (last 1000 routing decisions)
- **FR-11.2**: Periodic model fine-tuning with federated learning
- **FR-11.3**: Privacy-preserving gradient sharing between devices

### 2.4 Location Services
- **FR-12.1**: System captures GPS coordinates with accuracy measurement
- **FR-12.2**: **AI-optimized location updates**: Adaptive intervals (5-60s) based on movement
- **FR-12.3**: Minimum movement threshold: 5 meters
- **FR-12.4**: Location displayed on interactive map (OpenStreetMap)
- **FR-12.5**: **AI distance prediction**: Model estimates travel time to SOS location

### 2.5 Internet Connectivity
- **FR-13.1**: System probes for internet connectivity periodically
- **FR-13.2**: **AI identifies optimal gateway nodes** based on bandwidth and stability
- **FR-13.3**: Goal Nodes can deliver SOS to cloud services
- **FR-13.4**: **AI upload scheduling**: Model optimizes cloud upload timing

### 2.6 Data Persistence
- **FR-14.1**: System uses Hive for local storage
- **FR-14.2**: **AI model files** stored in app assets (~3-5MB total)
- **FR-14.3**: **Experience buffer** persists for on-device learning
- **FR-14.4**: User preferences and AI settings stored locally

---

## 3. Non-Functional Requirements

### 3.1 Performance
- **NFR-1.1**: AI routing decision latency < 50ms (95th percentile)
- **NFR-1.2**: NLP classification latency < 100ms (95th percentile)
- **NFR-1.3**: UI response time < 300ms for user interactions
- **NFR-1.4**: Support up to 100 concurrent mesh nodes
- **NFR-1.5**: Memory usage < 250MB including AI models
- **NFR-1.6**: **AI model loading time** < 2 seconds at app start

### 3.2 Reliability
- **NFR-2.1**: AI routing accuracy > 92% (measured against optimal path)
- **NFR-2.2**: NLP classification accuracy > 95% (F1-score on test set)
- **NFR-2.3**: Packet delivery success rate > 93% within 3 hops (with AI)
- **NFR-2.4**: **AI-predicted link failures** detected 85% of time before actual failure
- **NFR-2.5**: No data loss during app crashes or restarts

### 3.3 Scalability
- **NFR-3.1**: Support mesh networks with 50+ nodes
- **NFR-3.2**: Handle 100+ packets per minute
- **NFR-3.3**: **AI inference scales linearly** with O(n) complexity for n neighbors

### 3.4 AI Model Quality
- **NFR-4.1**: DQN convergence within 500K training episodes
- **NFR-4.2**: NLP model validation accuracy > 96%
- **NFR-4.3**: Model inference accuracy matches training accuracy (no overfitting)
- **NFR-4.4**: **Explainable AI**: User can view top 3 factors for each decision
- **NFR-4.5**: **Model robustness**: 90%+ accuracy under adversarial inputs

### 3.5 Battery Efficiency
- **NFR-5.1**: AI inference power consumption < 5% of total app power
- **NFR-5.2**: Battery drain < 12% per hour in relay mode (with AI)
- **NFR-5.3**: **AI power management**: Model predicts low-battery and reduces inference frequency
- **NFR-5.4**: Adaptive discovery intervals based on battery level

### 3.6 Compatibility
- **NFR-6.1**: Support Android 10 (API 29) and above
- **NFR-6.2**: TFLite models compatible with ARM, ARM64, x86, x86_64
- **NFR-6.3**: **Edge TPU support** on compatible devices (Pixel 4+, Samsung S21+)
- **NFR-6.4**: Graceful degradation on devices without NNAPI

---

## 4. AI System Architecture

### 4.1 Deep Q-Network (DQN) for Routing

#### 4.1.1 Model Architecture
```
Input Layer (6 features per neighbor):
  - RSSI Trend (5-sec moving avg): Float32
  - RSSI Variance: Float32
  - Battery Level: Float32 (0-100)
  - Battery Discharge Rate: Float32 (mAh/min)
  - Queue Congestion: Int32 (0-100)
  - Link Success Rate: Float32 (0-1)

Hidden Layer 1: Dense(64, ReLU)
Hidden Layer 2: Dense(32, ReLU)
Output Layer: Dense(1, Sigmoid) → Link Stability Score (0-1)

Optimizer: Adam (lr=0.001)
Loss: Huber Loss
Training Episodes: 1M
```

#### 4.1.2 Training Dataset
- **Simulation**: Custom mesh network simulator (10-100 nodes)
- **Scenarios**: 
  - Urban disaster (high density, intermittent power)
  - Rural disaster (sparse nodes, low battery)
  - Moving nodes (vehicles, responders)
- **Reward Function**:
```
  R = +10 (successful delivery) 
    + +5 (< 3 hops)
    + -5 (packet dropped)
    + -2 (retry needed)
    + -10 (loop detected)
```

#### 4.1.3 Inference Pipeline
```dart
// Pseudo-code
List<Neighbor> neighbors = getNeighbors();
for (neighbor in neighbors) {
  // Extract features
  List<double> features = [
    neighbor.rssiTrend,
    neighbor.rssiVariance,
    neighbor.batteryLevel,
    neighbor.batteryDischargeRate,
    neighbor.queueSize,
    neighbor.historicalSuccessRate
  ];
  
  // Run TFLite inference
  List<double> output = tfliteModel.runInference(features);
  neighbor.aiScore = output[0]; // 0.0 to 1.0
}

// Select neighbor with highest AI score
Neighbor bestNeighbor = neighbors.maxBy((n) => n.aiScore);
```

### 4.2 NLP Model for Emergency Classification

#### 4.2.1 Model Architecture
```
Option 1: LSTM-based (Lightweight)
  Embedding Layer: 10K vocab, 128 dims
  LSTM Layer 1: 128 units, return_sequences=True
  LSTM Layer 2: 64 units
  Dense Layer: 32 units, ReLU
  Output Layer: 3 units, Softmax → [P1, P2, P3]

Option 2: MobileBERT (Higher Accuracy)
  Pre-trained: MobileBERT-uncased (25M params)
  Fine-tuning: Last 2 layers
  Output Layer: 3 units, Softmax
  Quantization: 8-bit post-training quantization
```

#### 4.2.2 Training Dataset
- **Sources**:
  - Twitter disaster dataset (30K tweets)
  - Emergency call transcripts (10K samples)
  - Simulated disaster messages (10K samples)
- **Labels**:
  - CRITICAL (P1): 15K samples
  - WARNING (P2): 20K samples
  - GENERAL (P3): 15K samples
- **Augmentation**:
  - Synonym replacement
  - Back-translation (English ↔ Hindi ↔ English)
  - Character-level noise injection

#### 4.2.3 Inference Pipeline
```dart
// Pseudo-code
String userMessage = "My leg is bleeding heavily, trapped under debris";

// Tokenization
List<int> tokens = tokenizer.encode(userMessage);

// Pad to fixed length
List<int> paddedTokens = padSequence(tokens, maxLength: 128);

// Run TFLite inference
List<double> output = nlpModel.runInference(paddedTokens);
// output = [0.92, 0.05, 0.03] → P1: 92%, P2: 5%, P3: 3%

int predictedClass = argmax(output); // 0 (CRITICAL)
double confidence = output[predictedClass]; // 0.92

// Set packet priority
packet.priority = predictedClass + 1; // 1, 2, or 3
packet.aiConfidence = confidence;
```

---

## 5. User Interface Requirements (AI-Enhanced)

### 5.1 SOS Form Screen
- **UI-2.1**: Free-form text input with **real-time AI urgency indicator**
- **UI-2.2**: **AI confidence meter**: Shows classification confidence (0-100%)
- **UI-2.3**: **Suggested keywords**: AI suggests words to improve classification
- **UI-2.4**: Map showing current location
- **UI-2.5**: **AI-scored neighbor list**: Each neighbor shows Link Stability Score
- **UI-2.6**: **AI explanation card**: "Why this node was selected" (top 3 factors)
- **UI-2.7**: Large "SEND EMERGENCY SOS" button with AI priority badge

### 5.2 Relay Mode Screen
- **UI-4.1**: **AI Decision Timeline**: Shows last 20 routing decisions with explanations
- **UI-4.2**: **Model Performance Dashboard**:
  - AI routing accuracy: 94.2%
  - Predicted failures avoided: 17
  - Average inference time: 42ms
- **UI-4.3**: **Live Feature Visualization**: Real-time chart of RSSI, battery, congestion
- **UI-4.4**: **AI Confidence Heatmap**: Color-coded neighbor list
- **UI-4.5**: **Model Info**: Shows loaded model version and size

### 5.3 Diagnostic Screen
- **UI-5.1**: Wi-Fi P2P readiness status
- **UI-5.2**: **AI Model Status**:
  - DQN Model: Loaded ✓ (2.3MB, v1.0.0)
  - NLP Model: Loaded ✓ (4.1MB, v1.0.0)
  - Edge TPU: Available ✓
  - Inference Latency: 45ms (DQN), 87ms (NLP)
- **UI-5.3**: **AI Performance Metrics**:
  - Total inferences: 1,247
  - Successful predictions: 1,178 (94.5%)
  - Failed predictions: 69 (5.5%)
- **UI-5.4**: Packet history log with AI scores
- **UI-5.5**: **Model export**: Save experience buffer for analysis

---

## 6. Success Criteria (AI-Specific)

### 6.1 AI Performance
- **AI routing outperforms rule-based by >15%** in packet delivery rate
- **AI correctly classifies emergency severity >95%** of the time
- **AI predicts link failures >85%** accuracy before they occur
- **AI inference runs <50ms** on mid-range devices (Snapdragon 7xx series)

### 6.2 Technical Success
- Successful deployment of TFLite models on Android
- Edge TPU acceleration working on compatible devices
- AI explanations accepted by users as clear and helpful
- Zero AI-related crashes in production

### 6.3 User Success
- Users report **improved message delivery** compared to rule-based systems
- Emergency responders trust AI urgency classifications
- Relay nodes stay active longer due to **AI battery optimization**
- Positive feedback on **AI transparency** (explainable decisions)

---

## 7. AI Ethics & Safety

### 7.1 Fairness
- **AI-7.1**: Model tested for bias across languages and demographics
- **AI-7.2**: Equal classification accuracy for all emergency types
- **AI-7.3**: No geographic bias in routing decisions

### 7.2 Transparency
- **AI-7.4**: Users can view AI decision factors for each routing choice
- **AI-7.5**: Confidence scores displayed for all AI predictions
- **AI-7.6**: Model versioning visible to users

### 7.3 Safety
- **AI-7.7**: Fallback to rule-based routing if AI fails
- **AI-7.8**: AI cannot override user emergency classifications
- **AI-7.9**: Model updates require user consent
- **AI-7.10**: Privacy-preserving: No data leaves device

---

## Document Control

**Version**: 2.0 (AI-Powered)  
**Date**: February 16, 2026  
**Status**: Updated for AI for Bharat Hackathon  
**Author**: RescueNet AI Development Team  
**AI Framework**: TensorFlow Lite 2.14.0  
**Models**: DQN (2.3MB), MobileBERT (4.1MB)