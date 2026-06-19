package com.mcweb.connector.common;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

public final class ProcessedDeliveryStore {
    private final File file;
    private final Set<String> ids = new HashSet<>();

    public ProcessedDeliveryStore(File dataFolder) {
        if (!dataFolder.exists()) {
            dataFolder.mkdirs();
        }
        this.file = new File(dataFolder, "processed_deliveries.txt");
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
        } catch (IOException ignored) {
        }
    }

    private void persist() {
        try (BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(file), StandardCharsets.UTF_8))) {
            for (String id : ids) {
                writer.write(id);
                writer.newLine();
            }
        } catch (IOException ignored) {
        }
    }

    public Set<String> snapshot() {
        return Collections.unmodifiableSet(new HashSet<>(ids));
    }
}
