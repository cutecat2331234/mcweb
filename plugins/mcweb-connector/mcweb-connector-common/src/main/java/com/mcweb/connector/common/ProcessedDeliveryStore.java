package com.mcweb.connector.common;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;
import java.util.logging.Level;
import java.util.logging.Logger;

public final class ProcessedDeliveryStore {
    private static final Logger LOGGER = Logger.getLogger(ProcessedDeliveryStore.class.getName());
    private final File file;
    private final Set<String> ids = new HashSet<>();

    public ProcessedDeliveryStore(File dataFolder) {
        this(dataFolder, "processed_deliveries.txt");
    }

    public ProcessedDeliveryStore(File dataFolder, String filename) {
        if (!dataFolder.exists()) {
            dataFolder.mkdirs();
        }
        this.file = new File(dataFolder, filename);
        load();
    }

    public synchronized boolean contains(String deliveryId) {
        return deliveryId != null && ids.contains(deliveryId);
    }

    public synchronized void add(String deliveryId) {
        if (deliveryId == null || deliveryId.isEmpty() || ids.contains(deliveryId)) {
            return;
        }
        ids.add(deliveryId);
        persist();
    }

    public synchronized boolean registerIfNew(String id) {
        if (id == null || id.isEmpty() || ids.contains(id)) {
            return false;
        }
        ids.add(id);
        persist();
        return true;
    }

    public synchronized void remove(String id) {
        if (id != null && ids.remove(id)) {
            persist();
        }
    }

    private void load() {
        if (!file.exists()) {
            return;
        }
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (!line.trim().isEmpty()) {
                    ids.add(line.trim());
                }
            }
        } catch (IOException ex) {
            LOGGER.log(Level.WARNING, "Failed to load delivery store from " + file, ex);
        }
    }

    private void persist() {
        try (BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(file), StandardCharsets.UTF_8))) {
            for (String id : ids) {
                writer.write(id);
                writer.newLine();
            }
        } catch (IOException ex) {
            LOGGER.log(Level.WARNING, "Failed to persist delivery store to " + file, ex);
        }
    }

    public synchronized Set<String> snapshot() {
        return Collections.unmodifiableSet(new HashSet<>(ids));
    }
}
