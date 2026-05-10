package com.abhikr2100.soloquybackend;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

    @GetMapping("/hello")
    public Message hello() {
        return new Message("Hello, world!");
    }

    private record Message(String message) {}
}
