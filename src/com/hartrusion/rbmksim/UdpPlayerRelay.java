package com.hartrusion.rbmksim;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.SocketAddress;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.logging.Level;
import java.util.logging.Logger;

public class UdpPlayerRelay implements Runnable {

    private static final Logger LOGGER = Logger.getLogger(UdpPlayerRelay.class.getName());
    private final int port;
    private final Map<SocketAddress, Long> activeClients = new ConcurrentHashMap<>();

    public UdpPlayerRelay(int port) {
        this.port = port;
    }

    @Override
    public void run() {
        byte[] buffer = new byte[512];
        try (DatagramSocket socket = new DatagramSocket(port)) {
            LOGGER.log(Level.INFO, "UDP Player Relay listening on port {0}...", port);

            while (!socket.isClosed()) {
                DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
                socket.receive(packet);

                SocketAddress sender = packet.getSocketAddress();
                long now = System.currentTimeMillis();
                activeClients.put(sender, now);

                // Broadcast to all other active clients (prune clients silent > 5s)
                for (Map.Entry<SocketAddress, Long> entry : activeClients.entrySet()) {
                    if (now - entry.getValue() > 5000L) {
                        activeClients.remove(entry.getKey());
                        continue;
                    }
                    if (!entry.getKey().equals(sender)) {
                        DatagramPacket forward = new DatagramPacket(
                                packet.getData(), packet.getOffset(), packet.getLength(), entry.getKey());
                        socket.send(forward);
                    }
                }
            }
        } catch (IOException ex) {
            LOGGER.log(Level.SEVERE, "UDP Player Relay stopped", ex);
        }
    }
}
