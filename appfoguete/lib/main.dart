import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';


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
        print("linha: $json");
        print("ax: ${json['ax']}");
        final t = (json['t'] ?? 0).toDouble() / 1000;

        axData.add(FlSpot(t, (json['ax'] ?? 0).toDouble()));
          ayData.add(FlSpot(t, (json['ay'] ?? 0).toDouble()));
          azData.add(FlSpot(t, (json['az'] ?? 0).toDouble()));
          altData.add(FlSpot(t, (json['alt'] ?? 0).toDouble()));
          aTotalData.add(FlSpot(t, (json['a'] ?? 0).toDouble()));
      } catch (_) {
        print("JSON inválido: $linha");
      } finally {
        setState(() {
          axData;
          ayData;
          azData;
          altData;
        });
      }
    }
  }

  void _enviarComando() {
    if (connection != null && connection!.isConnected) {
      connection!.output.add(utf8.encode('a\n')); // "\n" importante para o ESP
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
              onPressed: _enviarComando,
              child: const Text('Receber dados do voo'),
              
            ),
            const SizedBox(height: 10),
            Column(
              children: [
                _buildGraph('Aceleração no eixo X', axData, Colors.red, 'Aceleração (g)'),
                _buildGraph('Aceleração no eixo Y', ayData, Colors.blue, 'Aceleração (g)'),
                _buildGraph('Aceleração no eixo Z', azData, Colors.green, 'Aceleração (g)'),
                _buildGraph('Aceleração Total', aTotalData, Colors.purple, 'Aceleração (g)'),
                _buildGraph('Altitude', altData, Colors.orange, 'Altitude (m)'),
              ],
            )
          ],
        ),
      ),
    );
  }
}
