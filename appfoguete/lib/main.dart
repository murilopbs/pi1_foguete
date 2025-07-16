import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(MaterialApp(home: BluetoothApp()));

class BluetoothApp extends StatefulWidget {
  @override
  _BluetoothAppState createState() => _BluetoothAppState();
}

class _BluetoothAppState extends State<BluetoothApp> {
  BluetoothConnection? connection;
  String status = 'Desconectado';
  String buffer = '';

  final List<FlSpot> axData = [];
  final List<FlSpot> ayData = [];
  final List<FlSpot> azData = [];
  final List<FlSpot> altData = [];
  final List<FlSpot> aTotalData = [];

  List<FlightData> allFlights = [];
  bool isReceivingAllFlights = false;
  FlightData? currentFlight;

  @override
  void initState() {
    super.initState();
    comeca();
  }

  Future<void> comeca() async {
    await solicitarPermissoes();
    _connectToDevice();
  }

  Future<void> solicitarPermissoes() async {
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request();
    await Permission.location.request();
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
  }

  void _connectToDevice() async {
    setState(() => status = 'Buscando dispositivos...');
    final devices = await FlutterBluetoothSerial.instance.getBondedDevices();

    final esp = devices.firstWhere(
      (d) => d.name?.contains('ESP') ?? false,
      orElse: () => throw Exception("ESP32 não emparelhado"),
    );

    setState(() => status = 'Conectando com ${esp.name}...');

    try {
      connection = await BluetoothConnection.toAddress(esp.address);
      setState(() => status = 'Conectado com ${esp.name}');

      connection!.input!.listen(_handleData);
    } catch (e) {
      setState(() => status = 'Erro na conexão: Dispositivo não encontrado');
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
        print("Dados recebidos: $json");

        if (json.containsKey('fim')) {
          if (currentFlight != null) {
            allFlights.add(currentFlight!);
            currentFlight = null;
          }

          if (!isReceivingAllFlights) {
            setState(() {});
          } else if (json['fim'] == true && currentFlight == null) {
            setState(() {
              status = 'Todos os voos recebidos!';
              _showFlightsList();
            });
          }
          return;
        }

        final t = (json['t'] ?? 0).toDouble() / 1000;

        if (!isReceivingAllFlights) {
          setState(() {
            axData.add(FlSpot(t, (json['ax'] ?? 0).toDouble()));
            ayData.add(FlSpot(t, (json['ay'] ?? 0).toDouble()));
            azData.add(FlSpot(t, (json['az'] ?? 0).toDouble()));
            altData.add(FlSpot(t, (json['alt'] ?? 0).toDouble()));
            aTotalData.add(FlSpot(t, (json['a'] ?? 0).toDouble()));
          });
        } else {
          if (currentFlight == null) {
            currentFlight = FlightData(
              name: 'Voo ${allFlights.length + 1}',
              axData: [],
              ayData: [],
              azData: [],
              altData: [],
              aTotalData: [],
            );
          }

          currentFlight!.axData.add(FlSpot(t, (json['ax'] ?? 0).toDouble()));
          currentFlight!.ayData.add(FlSpot(t, (json['ay'] ?? 0).toDouble()));
          currentFlight!.azData.add(FlSpot(t, (json['az'] ?? 0).toDouble()));
          currentFlight!.altData.add(FlSpot(t, (json['alt'] ?? 0).toDouble()));
          currentFlight!.aTotalData.add(FlSpot(t, (json['a'] ?? 0).toDouble()));
        }
      } catch (e) {
        print("Erro ao processar dados: $e");
        print("JSON inválido: $linha");
      }
    }
  }

  void _enviarComando(String comando) {
    if (connection != null && connection!.isConnected) {
      if (comando == 'a\n') {
        setState(() {
          isReceivingAllFlights = false;
          axData.clear();
          ayData.clear();
          azData.clear();
          altData.clear();
          aTotalData.clear();
          status = 'Recebendo dados do voo atual...';
        });
        connection!.output.add(utf8.encode(comando));
        connection!.output.allSent;
      } else if (comando == 'b\n') {
        setState(() {
          isReceivingAllFlights = true;
          allFlights.clear();
          status = 'Recebendo dados de todos os voos...';
        });
        connection!.output.add(utf8.encode(comando));
        connection!.output.allSent;
      }
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
              lineTouchData: LineTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                leftTitles: AxisTitles(
                  axisNameWidget: Text(
                    yAxisLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${(value * 1000).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                  axisNameWidget: const Text(
                    'Tempo (ms)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              borderData: FlBorderData(show: true),
              gridData: FlGridData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: data,
                  isCurved: true,
                  color: cor,
                  barWidth: 2,
                  dotData: FlDotData(show: false),
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

  FlightData({
    required this.name,
    required this.axData,
    required this.ayData,
    required this.azData,
    required this.altData,
    required this.aTotalData,
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
      String csvContent = "Tempo(ms),Aceleração X(g),Aceleração Y(g),Aceleração Z(g),Aceleração Total(g),Altitude(m)\n";
      
      int maxLength = flight.axData.length;
      if (flight.ayData.length != maxLength || 
          flight.azData.length != maxLength || 
          flight.aTotalData.length != maxLength || 
          flight.altData.length != maxLength) {
        throw Exception("Os dados do voo têm tamanhos inconsistentes");
      }
      
      for (int i = 0; i < maxLength; i++) {
        csvContent += "${(flight.axData[i].x * 1000).toStringAsFixed(0)},"
                     "${flight.axData[i].y.toStringAsFixed(6)},"
                     "${flight.ayData[i].y.toStringAsFixed(6)},"
                     "${flight.azData[i].y.toStringAsFixed(6)},"
                     "${flight.aTotalData[i].y.toStringAsFixed(6)},"
                     "${flight.altData[i].y.toStringAsFixed(2)}\n";
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(
          height: 150,
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                leftTitles: AxisTitles(
                  axisNameWidget: Text(
                    yAxisLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${(value * 1000).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                  axisNameWidget: const Text(
                    'Tempo (ms)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              borderData: FlBorderData(show: true),
              gridData: FlGridData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: data,
                  isCurved: true,
                  color: cor,
                  barWidth: 2,
                  dotData: FlDotData(show: false),
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
            icon: Icon(Icons.share),
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
          ],
        ),
      ),
    );
  }
}