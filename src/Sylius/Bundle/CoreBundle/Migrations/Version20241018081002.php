<?php

/*
 * This file is part of the Sylius package.
 *
 * (c) Sylius Sp. z o.o.
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

declare(strict_types=1);

namespace Sylius\Bundle\CoreBundle\Migrations;

use Doctrine\DBAL\Schema\Schema;
use Sylius\Bundle\CoreBundle\Doctrine\Migrations\AbstractPostgreSQLMigration;

final class Version20241018081002 extends AbstractPostgreSQLMigration
{
    public function getDescription(): string
    {
        return 'Add indexes to the Sylius address log table.';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('CREATE INDEX object_id_index ON sylius_address_log_entries (object_id)');
        $this->addSql('CREATE INDEX object_class_index ON sylius_address_log_entries (object_class)');
    }

    public function down(Schema $schema): void
    {
        $this->addSql('DROP INDEX object_id_index');
        $this->addSql('DROP INDEX object_class_index');
    }
}
