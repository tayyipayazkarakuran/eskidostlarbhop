<?php

declare(strict_types=1);

interface DataClient
{
    public function configured(): bool;

    public function get(string $path, array $query = []): array;

    /** @param array<string, array{0:string,1?:array}> $requests */
    public function multi(array $requests): array;
}
