import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
// A importação do flutter_bluetooth_serial é mantida para os tipos de dados, mas a lógica de conexão será mockada.
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async'; // Importado para usar o Future.delayed

// Início dos dados mockados (30 primeiros itens do voo15.txt)
// Fonte: voo15.txt
const String mockedFlightData = """
{"t":494,"ax":8.71615,"ay":-12.57212,"az":5.899681,"alt":1148.505,"a":16.39621,"volt":6.88}
{"t":944,"ax":4.950397,"ay":-17.31854,"az":5.036695,"alt":1148.517,"a":18.70312,"volt":7.01}
{"t":1393,"ax":8.480791,"ay":-17.08318,"az":3.271498,"alt":1148.501,"a":19.35101,"volt":7.01}
{"t":1842,"ax":7.186313,"ay":-18.7307,"az":0.407957,"alt":1148.452,"a":20.06611,"volt":6.94}
{"t":2291,"ax":6.519461,"ay":-14.25887,"az":-10.144,"alt":1148.73,"a":18.67403,"volt":6.95}
{"t":2740,"ax":6.048741,"ay":-13.35666,"az":-10.26168,"alt":1148.715,"a":17.89664,"volt":7.03}
{"t":3192,"ax":4.832717,"ay":-9.98317,"az":-11.43848,"alt":1148.711,"a":15.93291,"volt":7.11}
{"t":3640,"ax":5.107303,"ay":-9.198637,"az":-11.79152,"alt":1148.667,"a":15.80314,"volt":7.23}
{"t":4090,"ax":4.950397,"ay":-8.139519,"az":-9.869412,"alt":1149.297,"a":13.71727,"volt":7.25}
{"t":4538,"ax":4.871943,"ay":-7.354987,"az":-11.43848,"alt":1148.79,"a":14.44543,"volt":7.14}
{"t":4987,"ax":7.382446,"ay":-10.06162,"az":-11.28157,"alt":1148.644,"a":16.82292,"volt":7.28}
{"t":5439,"ax":8.088525,"ay":-12.06218,"az":-10.41858,"alt":1148.581,"a":17.87365,"volt":7.27}
{"t":5889,"ax":10.16753,"ay":-18.45612,"az":-3.475477,"alt":1148.604,"a":21.35617,"volt":6.97}
{"t":6337,"ax":8.127751,"ay":-19.51523,"az":-0.729615,"alt":1148.525,"a":21.15271,"volt":7.06}
{"t":6785,"ax":8.755377,"ay":-18.1423,"az":-1.35724,"alt":1148.605,"a":20.19014,"volt":7.18}
{"t":7235,"ax":7.813939,"ay":-18.37766,"az":-1.514147,"alt":1148.272,"a":20.0272,"volt":7.1}
{"t":7684,"ax":8.363111,"ay":-18.06385,"az":-1.121881,"alt":1148.604,"a":19.93747,"volt":7.79}
""";

void main() => runApp(MaterialApp(home: BluetoothApp(), debugShowCheckedModeBanner: false,));

class BluetoothApp extends StatefulWidget {
  @override
  _BluetoothAppState createState() => _BluetoothAppState();
}

class _BluetoothAppState extends State<BluetoothApp> {
  BluetoothConnection? connection;
  String status = 'Desconectado';
  String buffer = '';

  // Dados para o voo atual
  final List<FlSpot> axData = [];
  final List<FlSpot> ayData = [];
  final List<FlSpot> azData = [];
  final List<FlSpot> altData = [];
  final List<FlSpot> aTotalData = [];
  final List<FlSpot> voltData = [];
  final List<FlSpot> latData = [];
  final List<FlSpot> lngData = [];
  final List<FlSpot> gpsAltData = [];
  final List<FlSpot> velData = [];

  List<FlightData> allFlights = [];
  bool isReceivingAllFlights = false;
  FlightData? currentFlight;
  bool hasGpsData = false;

  @override
  void initState() {
    super.initState();
    // **CORREÇÃO**: A inicialização dos dados agora acontece após o primeiro frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await solicitarPermissoes();
      _startMockDataStream();
    });
  }

  Future<void> solicitarPermissoes() async {
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request();
    await Permission.location.request();
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
  }

  // Nova função para simular o recebimento de dados
  Future<void> _startMockDataStream() async {
    setState(() {
      isReceivingAllFlights = false;
      axData.clear();
      ayData.clear();
      azData.clear();
      altData.clear();
      aTotalData.clear();
      voltData.clear();
      latData.clear();
      lngData.clear();
      gpsAltData.clear();
      velData.clear();
      hasGpsData = false;
      status = 'Recebendo dados do voo atual...';
    });
    
    final lines = mockedFlightData.trim().split('\n');

    for (final line in lines) {
      if (mounted && line.isNotEmpty) {
        _handleData(utf8.encode('$line\n'));
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (mounted) {
      setState(() {
        status = 'Dados do voo recebidos';
      });
    }
  }

  void _handleData(Uint8List data) {
    buffer += utf8.decode(data);

    while (buffer.contains('\n')) {
      final index = buffer.indexOf('\n');
      final linha = buffer.substring(0, index).trim();
      buffer = buffer.substring(index + 1);

      if (linha.isEmpty) continue;

      try {
        final json = jsonDecode(linha);

        if (json.containsKey('fim')) {
           // Lógica para múltiplos voos (não usada neste mock)
          return;
        }

        final t = (json['t'] ?? 0).toDouble() / 1000;
        final hasGps = json.containsKey('lat') && json.containsKey('lng');

        if (!isReceivingAllFlights) {
          setState(() {
            axData.add(FlSpot(t, (json['ax'] ?? 0).toDouble()));
            ayData.add(FlSpot(t, (json['ay'] ?? 0).toDouble()));
            azData.add(FlSpot(t, (json['az'] ?? 0).toDouble()));
            altData.add(FlSpot(t, (json['alt'] ?? 0).toDouble()));
            aTotalData.add(FlSpot(t, (json['a'] ?? 0).toDouble()));
            voltData.add(FlSpot(t, (json['volt'] ?? 0).toDouble()));
            
            if (hasGps) {
              // ... lógica GPS
              hasGpsData = true;
            }
          });
        } else {
          // Lógica para múltiplos voos (não usada neste mock)
        }
      } catch (e) {
        print("Erro ao processar dados: $e");
        print("JSON inválido: $linha");
      }
    }
  }

  void _enviarComando(String comando) {
    if (comando == 'a\n') {
      _startMockDataStream();
    } else if (comando == 'b\n') {
      setState(() {
        status = 'Função "Todos os voos" não disponível com dados mockados.';
      });
    }
  }

  void _showFlightsList() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlightsListScreen(flights: allFlights),
      ),
    );
  }

  Widget _buildGraph(String label, List<FlSpot> data, Color cor, String yAxisLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(
          height: 150,
          child: LineChart(
            LineChartData(
              lineTouchData: const LineTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  axisNameWidget: Text(
                    yAxisLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      // **MELHORIA**: Mostra o tempo em segundos como inteiro.
                      return Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                    reservedSize: 30,
                  ),
                  axisNameWidget: const Text(
                    'Tempo (s)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              borderData: FlBorderData(show: true),
              gridData: const FlGridData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: data,
                  isCurved: true,
                  color: cor,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  void dispose() {
    connection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Grupo 1 Ajax")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('Status: $status'),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => _enviarComando('a\n'),
              child: const Text('Receber dados do voo'),
            ),
            ElevatedButton(
              onPressed: () => _enviarComando('b\n'),
              child: const Text('Receber dados de todos os voos'),
            ),
            const SizedBox(height: 10),
            if (!isReceivingAllFlights)
              Column(
                children: [
                  _buildGraph('Aceleração no eixo X', axData, Colors.red, 'Aceleração (g)'),
                  _buildGraph('Aceleração no eixo Y', ayData, Colors.blue, 'Aceleração (g)'),
                  _buildGraph('Aceleração no eixo Z', azData, Colors.green, 'Aceleração (g)'),
                  _buildGraph('Aceleração Total', aTotalData, Colors.purple, 'Aceleração (g)'),
                  _buildGraph('Altitude', altData, Colors.orange, 'Altitude (m)'),
                  _buildGraph('Voltagem', voltData, Colors.brown, 'Voltagem (V)'),
                  if (hasGpsData) ...[
                    _buildGraph('Latitude', latData, Colors.pink, 'Latitude'),
                    _buildGraph('Longitude', lngData, Colors.teal, 'Longitude'),
                    _buildGraph('Altitude GPS', gpsAltData, Colors.indigo, 'Altitude (m)'),
                    _buildGraph('Velocidade', velData, Colors.cyan, 'Velocidade (m/s)'),
                  ],
                ],
              )
            else
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

class FlightData {
  String name;
  List<FlSpot> axData;
  List<FlSpot> ayData;
  List<FlSpot> azData;
  List<FlSpot> altData;
  List<FlSpot> aTotalData;
  List<FlSpot> voltData;
  List<FlSpot> latData;
  List<FlSpot> lngData;
  List<FlSpot> gpsAltData;
  List<FlSpot> velData;
  bool hasGpsData;

  FlightData({
    required this.name,
    required this.axData,
    required this.ayData,
    required this.azData,
    required this.altData,
    required this.aTotalData,
    required this.voltData,
    required this.latData,
    required this.lngData,
    required this.gpsAltData,
    required this.velData,
    required this.hasGpsData,
  });
}

class FlightsListScreen extends StatelessWidget {
  final List<FlightData> flights;

  const FlightsListScreen({Key? key, required this.flights}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lista de Voos')),
      body: ListView.builder(
        itemCount: flights.length,
        itemBuilder: (context, index) {
          final flight = flights[index];
          return ListTile(
            title: Text(flight.name),
            subtitle: Text(flight.hasGpsData ? 'Com dados GPS' : 'Sem dados GPS'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => FlightDetailsScreen(flight: flight),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class FlightDetailsScreen extends StatelessWidget {
  final FlightData flight;

  const FlightDetailsScreen({Key? key, required this.flight}) : super(key: key);

  Future<void> _exportFlightData() async {
    try {
      String csvHeader = "Tempo(ms),Aceleração X(g),Aceleração Y(g),Aceleração Z(g),Aceleração Total(g),Altitude(m),Voltagem(V)";
      
      if (flight.hasGpsData) {
        csvHeader += ",Latitude,Longitude,Altitude GPS(m),Velocidade(m/s)";
      }
      
      String csvContent = "$csvHeader\n";
      
      int maxLength = flight.axData.length;
      
      for (int i = 0; i < maxLength; i++) {
        String line = "${(flight.axData[i].x * 1000).toStringAsFixed(0)},"
                     "${flight.axData[i].y.toStringAsFixed(6)},"
                     "${flight.ayData[i].y.toStringAsFixed(6)},"
                     "${flight.azData[i].y.toStringAsFixed(6)},"
                     "${flight.aTotalData[i].y.toStringAsFixed(6)},"
                     "${flight.altData[i].y.toStringAsFixed(2)},"
                     "${flight.voltData[i].y.toStringAsFixed(2)}";
        
        if (flight.hasGpsData) {
          line += ",${flight.latData[i].y.toStringAsFixed(6)},"
                  "${flight.lngData[i].y.toStringAsFixed(6)},"
                  "${flight.gpsAltData[i].y.toStringAsFixed(2)},"
                  "${flight.velData[i].y.toStringAsFixed(2)}";
        }
        
        csvContent += "$line\n";
      }
      
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${flight.name}_dados.csv');
      
      await file.writeAsString(csvContent);
      
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Dados do ${flight.name}',
        subject: 'Dados do voo do foguete',
      );
      
    } catch (e) {
      print("Erro ao exportar dados: $e");
    }
  }

  Widget _buildGraph(String label, List<FlSpot> data, Color cor, String yAxisLabel) {
    if (data.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(
          height: 150,
          child: LineChart(
            LineChartData(
              lineTouchData: const LineTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  axisNameWidget: Text(
                    yAxisLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                       return Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                     reservedSize: 30,
                  ),
                  axisNameWidget: const Text(
                    'Tempo (s)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              borderData: FlBorderData(show: true),
              gridData: const FlGridData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: data,
                  isCurved: true,
                  color: cor,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(flight.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exportFlightData,
            tooltip: 'Exportar dados',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _buildGraph('Aceleração no eixo X', flight.axData, Colors.red, 'Aceleração (g)'),
            _buildGraph('Aceleração no eixo Y', flight.ayData, Colors.blue, 'Aceleração (g)'),
            _buildGraph('Aceleração no eixo Z', flight.azData, Colors.green, 'Aceleração (g)'),
            _buildGraph('Aceleração Total', flight.aTotalData, Colors.purple, 'Aceleração (g)'),
            _buildGraph('Altitude', flight.altData, Colors.orange, 'Altitude (m)'),
            _buildGraph('Voltagem', flight.voltData, Colors.brown, 'Voltagem (V)'),
            if (flight.hasGpsData) ...[
              _buildGraph('Latitude', flight.latData, Colors.pink, 'Latitude'),
              _buildGraph('Longitude', flight.lngData, Colors.teal, 'Longitude'),
              _buildGraph('Altitude GPS', flight.gpsAltData, Colors.indigo, 'Altitude (m)'),
              _buildGraph('Velocidade', flight.velData, Colors.cyan, 'Velocidade (m/s)'),
            ],
          ],
        ),
      ),
    );
  }
}