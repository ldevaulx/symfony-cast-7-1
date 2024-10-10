<?php

namespace App\Controller;

use Psr\Log\LoggerInterface;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

class StarshipApiController extends AbstractController
{
    #[Route('/api/starships')]
    public function getCollection(LoggerInterface $logger) : Response
    {
        $logger->info('Starship collection retrieved');
        $starships = [
            [
                'name' => 'USS LeafyCruiser (NCC-0001)',
                'class' => 'Garden',
                'captain' => 'Jean-Luc Pickles',
                'status' => 'taken over by Q',
            ],
            [
                'name' => 'USS Espresso (NCC-1234-C)',
                'class' => 'Latte',
                'captain' => 'James T. Quick!',
                'status' => 'repaired',
            ],
            [
                'name' => 'USS Wanderlust (NCC-2024-W)',
                'class' => 'Delta Tourist',
                'captain' => 'Kathryn Journeyway',
                'status' => 'under construction',
            ],
        ];
        return $this->json($starships);
    }
}