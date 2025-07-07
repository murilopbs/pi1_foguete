import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(MaterialApp(home: BluetoothApp()));

class BluetoothApp extends StatefulWidget {
  @override
  _BluetoothAppState createState() => _BluetoothAppState();
}

class _BluetoothAppState extends State<BluetoothApp> {
  BluetoothConnection? connection;
  String status = 'Desconectado';

  final List<FlSpot> axData = [];
  final List<FlSpot> ayData = [];
  final List<FlSpot> azData = [];
  final List<FlSpot> altData = [];
  final List<FlSpot> aTotalData = [];

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

      connection!.input!.listen((data) {
        final linha = utf8.decode(data).trim();

        for (final l in LineSplitter.split(linha)) {
          try {
            final json = jsonDecode(l);
            final t = (json['t'] ?? 0).toDouble() / 1000; // tempo em segundos

            setState(() {
              axData.add(FlSpot(t, (json['ax'] ?? 0).toDouble()));
              ayData.add(FlSpot(t, (json['ay'] ?? 0).toDouble()));
              azData.add(FlSpot(t, (json['az'] ?? 0).toDouble()));
              altData.add(FlSpot(t, (json['alt'] ?? 0).toDouble()));
              aTotalData.add(FlSpot(t, (json['a'] ?? 0).toDouble()));

              _limitarDados(axData);
              _limitarDados(ayData);
              _limitarDados(azData);
              _limitarDados(altData);
              _limitarDados(aTotalData);
            });
          } catch (_) {
            print("Linha inválida: $linha");
          }
        }
      });
    } catch (e) {
      setState(() => status = 'Erro na conexão: Dispositivo não encontrado');
    }
  }

  void _limitarDados(List<FlSpot> lista, [int max = 100]) {
    if (lista.length > max) {
      lista.removeRange(0, lista.length - max);
    }
  }

  void _enviarComando() {
    if (connection != null && connection!.isConnected) {
      connection!.output.add(utf8.encode('a'));
      connection!.output.allSent;
      setState(() => status = 'Comando enviado!');
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
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
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
                        '${(value * 1000).toStringAsFixed(0)}', // Converte para ms
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
      appBar: AppBar(title: const Text("Foguete 🚀")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('Status: $status'),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _enviarComando,
              child: const Text('Receber dados do voo'),
            ),
            const SizedBox(height: 10),
            Visibility(
              //visible: status.contains("Conectado") ? true : false, deu ruim kkkkk depois ver o pq
              visible: true,
              child: Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildGraph('Aceleração no eixo X', axData, Colors.red, 'Aceleração (g)'),
                      _buildGraph('Aceleração no eixo Y', ayData, Colors.blue, 'Aceleração (g)'),
                      _buildGraph('Aceleração no eixo Z', azData, Colors.green, 'Aceleração (g)'),
                      _buildGraph('Aceleração Total', aTotalData, Colors.purple, 'Aceleração (g)'),
                      _buildGraph('Altitude', altData, Colors.orange, 'Altitude (m)'),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
