/*
 * Copyright (C) 2025 Viktor Alexander Hartung
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
package com.hartrusion.rbmksim;

import com.hartrusion.mvc.net.SocketServer;
import java.io.IOException;
import java.util.Arrays;
import com.hartrusion.modeling.solvers.DomainAnalogySolver;
import java.util.ArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;
import java.util.logging.Logger;
import javax.swing.UIManager;
import javax.swing.plaf.metal.MetalLookAndFeel;
import com.hartrusion.mvc.AwtUpdater;
import com.hartrusion.mvc.Controller;
import com.hartrusion.rbmksim.gui.elements.ChornobylMetalTheme;
import com.hartrusion.util.SimpleLogOut;
// import com.formdev.flatlaf.FlatDarkLaf;

/**
 *
 * @author Viktor Alexander Hartung
 */
public class RbmkSimulator {

    MainLoop mainLoop;

    private final ScheduledExecutorService scheduler;
    private final ExecutorService threadPool;

    RbmkSimulator() {
        scheduler = Executors.newSingleThreadScheduledExecutor(
                new ThreadFactory() {
                    private final ThreadFactory defaultThreadFactory = Executors.defaultThreadFactory();

                    @Override
                    public Thread newThread(Runnable r) {
                        Thread t = defaultThreadFactory.newThread(r);
                        t.setPriority(Thread.MAX_PRIORITY - 1);
                        return t;
                    }
                });

        // Initialize Multithreading for SuperPosition solver
        int cores = Runtime.getRuntime().availableProcessors();
        threadPool = Executors.newFixedThreadPool(cores);
        DomainAnalogySolver.setThreadPool(threadPool);

        mainLoop = new MainLoop();
    }

    private void run(boolean headless) {
        Controller contr = new Controller();
        contr.registerModel(mainLoop);
        mainLoop.registerController(contr);
        mainLoop.init();

        if (headless) {
            // Start TCP SocketServer on port 26486 without any Swing GUI
            SocketServer server = new SocketServer(contr, CommBlueprints.createCommBlueprints());
            Thread serverThread = new Thread(() -> {
                try {
                    server.startServer(26486);
                } catch (IOException ex) {
                    Logger.getLogger(RbmkSimulator.class.getName()).log(Level.SEVERE, "Server failed", ex);
                }
            }, "RbmkSocketServer");
            serverThread.setDaemon(false);
            serverThread.start();
            new Thread(new UdpPlayerRelay(26486), "RbmkUdpRelay").start();
        } else {
            // Original Swing GUI startup
            try {
                for (UIManager.LookAndFeelInfo info : UIManager.getInstalledLookAndFeels()) {
                    if ("Metal".equals(info.getName())) {
                        MetalLookAndFeel.setCurrentTheme(new ChornobylMetalTheme());
                        UIManager.setLookAndFeel(info.getClassName());
                        break;
                    }
                }
            } catch (Exception ex) {
                Logger.getLogger(RbmkSimulator.class.getName()).log(Level.SEVERE, null, ex);
            }

            ControlPanelManager view = new ControlPanelManager();
            AwtUpdater updt = new AwtUpdater();
            contr.registerUpdater(updt);
            updt.registerView(view);
            view.registerController(contr);
            view.setAlarmList(new ArrayList<>(mainLoop.alarms.getAlarmList()));

            java.awt.EventQueue.invokeLater(view::displayNewControlPanel);
        }

        // Start the 100 ms cyclic reactor simulation thread
        scheduler.scheduleAtFixedRate(mainLoop, 100, 100, TimeUnit.MILLISECONDS);
    }

    public static void main(String[] args) {
        SimpleLogOut.configureLoggingToStdOut();
        boolean headless = Arrays.asList(args).contains("--headless");

        RbmkSimulator app = new RbmkSimulator();
        app.run(headless);
    }

}
