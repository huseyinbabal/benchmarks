package com.example;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.java21.instrument.VirtualThreadMetrics;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class SpringBoot4ServerApplication {
    public static void main(String[] args) {
        SpringApplication.run(SpringBoot4ServerApplication.class, args);
    }

    @Bean
    VirtualThreadMetrics virtualThreadMetrics(MeterRegistry registry) {
        VirtualThreadMetrics metrics = new VirtualThreadMetrics();
        metrics.bindTo(registry);
        return metrics;
    }
}